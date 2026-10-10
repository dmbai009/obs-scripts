-- OBS Timestamp — v2.0
-- Timemarks, configurable folder, manual/automatic stream title naming.
-- Windows: automatic title lookup uses yt-dlp.exe (metadata ONLY, no download).
-- Keeps the hotkey ID and stored settings from the original timestamp.lua.

local obs = obslua
local hotkey_id = obs.OBS_INVALID_HOTKEY_ID
local DEBOUNCE_MS = 500
local LOOKUP_RETRY_SECONDS = 25
local LOOKUP_MAX_ATTEMPTS = 8

local offset = -30
local save_dir = ""
local naming_mode = "auto" -- auto | manual | date
local manual_title = ""
local channel_url = ""
local ytdlp_path = ""
local last_press_ms = 0
local session = nil
local title_job = nil
local lookup_attempts = 0
local lookup_next_at = 0
local lookup_generation = 0
local poll_registered = false

local function log(level, msg)
    obs.script_log(level, "[Timestamp] " .. msg)
end

local is_windows = (package.config:sub(1, 1) == "\\")
local sep = is_windows and "\\" or "/"

local function join_path(folder, name)
    if folder:sub(-1) == "\\" or folder:sub(-1) == "/" then
        return folder .. name
    end
    return folder .. sep .. name
end

local function default_folder()
    if is_windows then
        local profile = os.getenv("USERPROFILE")
        if profile and profile ~= "" then return join_path(profile, "Desktop") end
    end
    local home = os.getenv("HOME")
    if home and home ~= "" then return join_path(home, "Desktop") end
    return script_path()
end

local win = nil
local ffi = nil
if is_windows then
    local ok, lib = pcall(require, "ffi")
    if ok then
        ffi = lib
        local cdef_ok, err = pcall(ffi.cdef, [[
            typedef struct {
                unsigned long cb; wchar_t *lpReserved; wchar_t *lpDesktop;
                wchar_t *lpTitle; unsigned long dwX; unsigned long dwY;
                unsigned long dwXSize; unsigned long dwYSize;
                unsigned long dwXCountChars; unsigned long dwYCountChars;
                unsigned long dwFillAttribute; unsigned long dwFlags;
                unsigned short wShowWindow; unsigned short cbReserved2;
                unsigned char *lpReserved2; void *hStdInput;
                void *hStdOutput; void *hStdError;
            } OBS_TS_STARTUPINFOW;
            typedef struct {
                void *hProcess; void *hThread;
                unsigned long dwProcessId; unsigned long dwThreadId;
            } OBS_TS_PROCESS_INFORMATION;
            int __stdcall MultiByteToWideChar(unsigned int, unsigned long,
                const char*, int, wchar_t*, int);
            void* __stdcall CreateFileW(const wchar_t*, unsigned long,
                unsigned long, void*, unsigned long, unsigned long, void*);
            int __stdcall ReadFile(void*, void*, unsigned long, unsigned long*, void*);
            int __stdcall WriteFile(void*, const void*, unsigned long, unsigned long*, void*);
            unsigned long __stdcall SetFilePointer(void*, long, long*, unsigned long);
            int __stdcall CloseHandle(void*);
            unsigned long __stdcall GetFileAttributesW(const wchar_t*);
            int __stdcall DeleteFileW(const wchar_t*);
            int __stdcall MoveFileW(const wchar_t*, const wchar_t*);
            int __stdcall CreateProcessW(const wchar_t*, wchar_t*, void*, void*,
                int, unsigned long, void*, const wchar_t*,
                OBS_TS_STARTUPINFOW*, OBS_TS_PROCESS_INFORMATION*);
            int __stdcall GetExitCodeProcess(void*, unsigned long*);
            int __stdcall TerminateProcess(void*, unsigned int);
            unsigned long __stdcall GetLastError(void);
        ]])
        if cdef_ok then
            win = ffi.load("kernel32")
        else
            log(obs.LOG_WARNING, "Windows API unavailable: " .. tostring(err))
        end
    end
end

local function wstr(s)
    local n = win.MultiByteToWideChar(65001, 0, s, #s, nil, 0)
    if n == 0 then return nil end
    local buf = ffi.new("wchar_t[?]", n + 1)
    if win.MultiByteToWideChar(65001, 0, s, #s, buf, n) == 0 then return nil end
    buf[n] = 0
    return buf
end

local function exists(path)
    if win then
        local p = wstr(path)
        return p ~= nil and tonumber(win.GetFileAttributesW(p)) ~= 0xFFFFFFFF
    end
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

local function read_small_file(path)
    if win then
        local p = wstr(path)
        if not p then return nil end
        local h = win.CreateFileW(p, 0x80000000, 0x00000001 + 0x00000002,
            nil, 3, 0x80, nil)
        if h == ffi.cast("void*", -1) then return nil end
        local buffer = ffi.new("char[?]", 32768)
        local got = ffi.new("unsigned long[1]")
        local ok = win.ReadFile(h, buffer, 32768, got, nil) ~= 0
        win.CloseHandle(h)
        if ok and got[0] > 0 then return ffi.string(buffer, got[0]) end
        return nil
    end
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read(32768)
    f:close()
    return data
end

local function append_text(path, content)
    if win then
        local p = wstr(path)
        if not p then return false end
        local h = win.CreateFileW(p, 0x40000000, 1, nil, 4, 0x80, nil)
        if h == ffi.cast("void*", -1) then return false end
        win.SetFilePointer(h, 0, nil, 2) -- FILE_END
        local written = ffi.new("unsigned long[1]")
        local ok = win.WriteFile(h, content, #content, written, nil) ~= 0
        win.CloseHandle(h)
        return ok and tonumber(written[0]) == #content
    end
    local f = io.open(path, "ab")
    if not f then return false end
    local ok = f:write(content)
    f:close()
    return ok ~= nil
end

local function remove_file(path)
    if win then
        local p = wstr(path)
        if p then win.DeleteFileW(p) end
    else
        os.remove(path)
    end
end

local function rename_file(old, new)
    if win then
        local a, b = wstr(old), wstr(new)
        return a ~= nil and b ~= nil and win.MoveFileW(a, b) ~= 0
    end
    if exists(new) then return false end
    return os.rename(old, new) ~= nil
end

local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

local function safe_title(value)
    value = (value or ""):gsub("[\\/:*?\"<>|]", " ")
        :gsub("[%c]", " "):gsub("%s+", " ")
    value = trim(value):gsub("[%. ]+$", "")
    -- Cap by UTF-8 character boundaries rather than slicing Cyrillic in half.
    local result = ""
    for char in value:gmatch("[\1-\127\194-\244][\128-\191]*") do
        if #result + #char > 120 then break end
        result = result .. char
    end
    result = result:gsub("[%. ]+$", "")
    local upper = result:upper()
    local stem = upper:match("^([^.]+)") or upper
    local reserved = (stem == "CON" or stem == "PRN" or stem == "AUX"
        or stem == "NUL" or stem:match("^COM[1-9]$")
        or stem:match("^LPT[1-9]$"))
    if reserved then result = "_" .. result end
    return result ~= "" and result or "stream_timestamps"
end

local function format_time(seconds)
    seconds = math.max(0, seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

-- Keep the old behaviour: prefer streaming output over recording output.
local function get_current_time()
    local output
    if obs.obs_frontend_streaming_active() then
        output = obs.obs_frontend_get_streaming_output()
    elseif obs.obs_frontend_recording_active() then
        output = obs.obs_frontend_get_recording_output()
    end
    local seconds = 0
    if output then
        local total_frames = obs.obs_output_get_total_frames(output)
        local vi = obs.obs_video_info()
        if obs.obs_get_video_info(vi) and vi.fps_den ~= 0 then
            local fps = vi.fps_num / vi.fps_den
            if fps > 0 then seconds = total_frames / fps end
        end
        obs.obs_output_release(output)
    end
    return seconds
end

local function choose_name(title, current_path)
    local stem = safe_title(title) .. "_" .. session.started_at
    for i = 1, 999 do
        local name = stem .. (i == 1 and "" or "_" .. i) .. ".txt"
        local path = join_path(session.folder, name)
        if path == current_path or not exists(path) then return name, path end
    end
    return nil, nil
end

local function apply_title(title)
    if not session then return end
    title = trim(title)
    if title == "" then return end
    local name, path = choose_name(title, session.file_path)
    if not path or path == session.file_path then return end
    if session.has_saved and not rename_file(session.file_path, path) then
        log(obs.LOG_WARNING, "Cannot rename timestamp file; keeping: " .. session.file_path)
        return
    end
    session.filename = name
    session.file_path = path
    session.title_received = true
    log(obs.LOG_INFO, "File name: " .. name)
end

local function close_job(terminate)
    if not title_job then return end
    if terminate and win then win.TerminateProcess(title_job.handle, 1) end
    if win then win.CloseHandle(title_job.handle) end
    remove_file(title_job.result_path)
    title_job = nil
end

local function windows_quote(s)
    -- Windows CommandLineToArgvW compatible quoting (no cmd.exe invocation).
    local result = '"'
    local slash_count = 0
    for i = 1, #s do
        local c = s:sub(i, i)
        if c == "\\" then
            slash_count = slash_count + 1
        elseif c == '"' then
            result = result .. string.rep("\\", slash_count * 2 + 1) .. '"'
            slash_count = 0
        else
            result = result .. string.rep("\\", slash_count) .. c
            slash_count = 0
        end
    end
    return result .. string.rep("\\", slash_count * 2) .. '"'
end

local function begin_title_fetch()
    if not session or not win or not obs.obs_frontend_streaming_active()
        or naming_mode ~= "auto" or session.title_received or title_job then return end
    if trim(channel_url) == "" or not channel_url:match("^https?://") then return end
    if lookup_attempts >= LOOKUP_MAX_ATTEMPTS then return end

    lookup_attempts = lookup_attempts + 1
    lookup_next_at = os.time() + LOOKUP_RETRY_SECONDS
    local exe = trim(ytdlp_path)
    if exe == "" then
        local adjacent = join_path(script_path(), "yt-dlp.exe")
        exe = exists(adjacent) and adjacent or "yt-dlp.exe"
    end
    local temp_dir = os.getenv("TEMP") or os.getenv("TMP") or session.folder
    local result_file = join_path(temp_dir,
        "obs_timestamp_title_" .. tostring(math.floor(obs.os_gettime_ns() / 1000000))
        .. "_" .. tostring(lookup_generation) .. ".txt")
    remove_file(result_file)

    local args = {
        exe, "--ignore-config", "--no-playlist", "--no-warnings", "--quiet",
        "--socket-timeout", "8", "--extractor-retries", "1", "--retries", "1",
        "--ignore-no-formats-error", "--print-to-file", "%(title)s",
        result_file, "--", channel_url
    }
    local pieces = {}
    for _, arg in ipairs(args) do pieces[#pieces + 1] = windows_quote(arg) end
    local command_line = wstr(table.concat(pieces, " "))
    if not command_line then return end

    local si = ffi.new("OBS_TS_STARTUPINFOW[1]")
    si[0].cb = ffi.sizeof("OBS_TS_STARTUPINFOW")
    local pi = ffi.new("OBS_TS_PROCESS_INFORMATION[1]")
    local ok = win.CreateProcessW(nil, command_line, nil, nil, 0, 0x08000000,
        nil, nil, si, pi)
    if ok == 0 then
        if lookup_attempts == 1 then
            log(obs.LOG_WARNING, "yt-dlp couldn't start (Win32 error " ..
                tostring(win.GetLastError()) .. "). Choose yt-dlp.exe in settings.")
        end
        return
    end
    win.CloseHandle(pi[0].hThread)
    title_job = { handle = pi[0].hProcess, result_path = result_file,
        generation = lookup_generation }
end

local function ensure_session()
    if session then return end
    local folder = trim(save_dir)
    if folder == "" then folder = default_folder() end
    session = {
        folder = folder,
        started_at = os.date("%Y-%m-%d_%H-%M-%S"),
        file_path = nil, filename = nil,
        has_saved = false, title_received = false,
    }
    last_press_ms = 0
    lookup_attempts = 0
    lookup_next_at = 0
    lookup_generation = lookup_generation + 1
    local initial_title = naming_mode == "date" and "stream_timestamps"
        or (trim(manual_title) ~= "" and manual_title or "stream_timestamps")
    local name, path = choose_name(initial_title)
    session.filename, session.file_path = name, path
    session.title_received = naming_mode == "manual" or naming_mode == "date"
    if naming_mode == "auto" then begin_title_fetch() end
end

local function check_title_job()
    if not title_job or not win then return end
    local code = ffi.new("unsigned long[1]")
    if win.GetExitCodeProcess(title_job.handle, code) == 0 then
        close_job(true)
        return
    end
    if tonumber(code[0]) == 259 then return end -- STILL_ACTIVE
    local generation = title_job.generation
    local result = read_small_file(title_job.result_path)
    close_job(false)
    if not session or generation ~= lookup_generation then return end
    if result then
        -- --print-to-file writes one line; discard trailing newline and BOM.
        result = result:gsub("^\239\187\191", "")
        result = result:match("([^\r\n]+)") or ""
        if trim(result) ~= "" and result ~= "NA" then
            apply_title(result)
        end
    end
end

local function poll_title()
    if title_job then check_title_job() end
    if session and not session.title_received and naming_mode == "auto"
        and obs.obs_frontend_streaming_active() and not title_job
        and os.time() >= lookup_next_at then
        begin_title_fetch()
    end
end

function script_description()
    return "Save timestamp markers during a stream or recording using an OBS hotkey. " ..
        "Choose an output folder and a filename based on the date, a custom title, " ..
        "or the live stream title retrieved with yt-dlp.exe (Windows). " ..
        "If title lookup fails, timestamp markers are still saved."
end

function script_properties()
    local props = obs.obs_properties_create()
    obs.obs_properties_add_int(props, "offset", "Time Offset (seconds)", -3600, 3600, 1)
    obs.obs_properties_add_path(props, "save_dir", "Timestamp Output Folder",
        obs.OBS_PATH_DIRECTORY, "", nil)
    local modes = obs.obs_properties_add_list(props, "naming_mode", "Filename Mode",
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(modes, "Automatic from Stream URL (yt-dlp)", "auto")
    obs.obs_property_list_add_string(modes, "Manual Title", "manual")
    obs.obs_property_list_add_string(modes, "Date Only", "date")
    obs.obs_properties_add_text(props, "manual_title", "Title / Fallback Title",
        obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "channel_url",
        "Stream or Channel URL (automatic mode)", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_path(props, "ytdlp_path", "yt-dlp.exe (automatic mode, Windows)",
        obs.OBS_PATH_FILE, "Executables (*.exe);;All files (*.*)", nil)
    return props
end

function script_defaults(settings)
    obs.obs_data_set_default_int(settings, "offset", -30)
    obs.obs_data_set_default_string(settings, "save_dir", default_folder())
    obs.obs_data_set_default_string(settings, "naming_mode", "auto")
    obs.obs_data_set_default_string(settings, "manual_title", "")
    obs.obs_data_set_default_string(settings, "channel_url", "")
    obs.obs_data_set_default_string(settings, "ytdlp_path", "")
end

function script_update(settings)
    offset = obs.obs_data_get_int(settings, "offset")
    save_dir = obs.obs_data_get_string(settings, "save_dir")
    naming_mode = obs.obs_data_get_string(settings, "naming_mode")
    if naming_mode ~= "auto" and naming_mode ~= "manual" and naming_mode ~= "date" then
        naming_mode = "auto"
    end
    manual_title = obs.obs_data_get_string(settings, "manual_title")
    channel_url = trim(obs.obs_data_get_string(settings, "channel_url"))
    ytdlp_path = obs.obs_data_get_string(settings, "ytdlp_path")
end

local function save_timestamp()
    if not (obs.obs_frontend_streaming_active() or obs.obs_frontend_recording_active()) then
        return
    end
    local now_ms = obs.os_gettime_ns() / 1000000
    if now_ms - last_press_ms < DEBOUNCE_MS then return end
    ensure_session()
    local timestamp = format_time(get_current_time() + offset)
    if append_text(session.file_path, timestamp .. "\n") then
        session.has_saved = true
        last_press_ms = now_ms
        log(obs.LOG_INFO, "Saved " .. timestamp .. " -> " .. session.filename)
    else
        -- Don't debounce failed writes: user can fix the folder and try again.
        log(obs.LOG_WARNING, "Cannot write timestamp to: " .. session.file_path)
    end
end

local function on_hotkey(pressed)
    if pressed then save_timestamp() end
end

local function on_event(event)
    if event == obs.OBS_FRONTEND_EVENT_STREAMING_STARTED or
       event == obs.OBS_FRONTEND_EVENT_RECORDING_STARTED then
        ensure_session()
        if session and naming_mode == "auto" and obs.obs_frontend_streaming_active() then
            begin_title_fetch()
        end
    elseif event == obs.OBS_FRONTEND_EVENT_STREAMING_STOPPED or
           event == obs.OBS_FRONTEND_EVENT_RECORDING_STOPPED then
        if not (obs.obs_frontend_streaming_active() or obs.obs_frontend_recording_active()) then
            close_job(true)
            session = nil
            lookup_generation = lookup_generation + 1
        end
    end
end

function script_load(settings)
    hotkey_id = obs.obs_hotkey_register_frontend(
        "save_timestamp_hotkey", "Save Timestamp", on_hotkey)
    local saved = obs.obs_data_get_array(settings, "save_timestamp_hotkey")
    if saved then
        obs.obs_hotkey_load(hotkey_id, saved)
        obs.obs_data_array_release(saved)
    end
    obs.obs_frontend_add_event_callback(on_event)
    if not poll_registered then
        obs.timer_add(poll_title, 1000)
        poll_registered = true
    end
end

function script_save(settings)
    local saved = obs.obs_hotkey_save(hotkey_id)
    obs.obs_data_set_array(settings, "save_timestamp_hotkey", saved)
    obs.obs_data_array_release(saved)
end

function script_unload()
    if poll_registered then
        obs.timer_remove(poll_title)
        poll_registered = false
    end
    close_job(true)
end
