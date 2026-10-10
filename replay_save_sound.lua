-- Replay Save Sound - configurable OBS Studio Lua script
-- Plays a sound when OBS successfully saves a Replay Buffer clip.
-- Uses the OBS Media Source (FFmpeg) instead of Windows PlaySound.
-- Sound is routed to the OBS monitoring device only, not to OBS audio tracks.

local obs = obslua

local sound_file = ""
local volume_percent = 50
local player = nil

local function log_warning(message)
    obs.script_log(obs.LOG_WARNING, "[Replay Save Sound] " .. message)
end

local function stop_player()
    if player == nil then
        return
    end

    obs.obs_source_media_stop(player)
    obs.obs_source_dec_active(player)
    obs.obs_source_release(player)
    player = nil
end

local function play_notification()
    if sound_file == "" then
        log_warning("No sound file selected. Choose a file in Tools > Scripts.")
        return
    end

    -- Stop any previous notification so repeated saves play from the start.
    stop_player()

    local settings = obs.obs_data_create()
    obs.obs_data_set_bool(settings, "is_local_file", true)
    obs.obs_data_set_string(settings, "local_file", sound_file)
    obs.obs_data_set_bool(settings, "looping", false)
    obs.obs_data_set_bool(settings, "restart_on_activate", true)
    obs.obs_data_set_bool(settings, "close_when_inactive", true)

    -- A private source does not appear in your Scenes/Sources list.
    local source = obs.obs_source_create_private(
        "ffmpeg_source", "Replay Save Sound (private)", settings
    )
    obs.obs_data_release(settings)

    if source == nil then
        log_warning("Failed to create an OBS Media Source. Check your OBS log.")
        return
    end

    obs.obs_source_set_volume(source, volume_percent / 100.0)

    -- The sound should be heard locally, not inserted into OBS recordings.
    obs.obs_source_set_audio_mixers(source, 0)
    obs.obs_source_set_monitoring_type(source, obs.OBS_MONITORING_TYPE_MONITOR_ONLY)

    player = source
    -- Activating the source starts playback (restart_on_activate = true).
    obs.obs_source_inc_active(player)
end

local function test_sound_clicked(properties, property)
    play_notification()
    return false
end

local function on_event(event)
    if event == obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_SAVED then
        play_notification()
    end
end

function script_description()
    return [[
Play a notification sound when OBS saves a Replay Buffer clip.

1. Select an audio file (WAV, MP3, OGG, FLAC, etc.).
2. Adjust the volume.
3. Click "Test Sound" to preview the notification.

The sound is sent to your OBS monitoring device:
Settings > Audio > Advanced > Monitoring Device.
It is not sent directly to OBS recording or streaming audio tracks.

If OBS captures desktop audio from the same device, the notification
may still be included in your recording or stream through desktop audio capture.
]]
end

function script_properties()
    local properties = obs.obs_properties_create()

    obs.obs_properties_add_path(
        properties,
        "sound_file",
        "Sound File",
        obs.OBS_PATH_FILE,
        "Audio files (*.wav *.mp3 *.ogg *.flac *.aac *.m4a *.wma);;All files (*.*)",
        nil
    )

    local slider = obs.obs_properties_add_int_slider(
        properties, "volume_percent", "Volume", 0, 100, 1
    )
    obs.obs_property_int_set_suffix(slider, "%")

    obs.obs_properties_add_button(
        properties, "test_sound", "Test Sound", test_sound_clicked
    )

    return properties
end

function script_defaults(settings)
    obs.obs_data_set_default_string(settings, "sound_file", "")
    obs.obs_data_set_default_int(settings, "volume_percent", 50)
end

function script_update(settings)
    local new_file = obs.obs_data_get_string(settings, "sound_file")
    local new_volume = obs.obs_data_get_int(settings, "volume_percent")
    new_volume = math.max(0, math.min(100, new_volume))

    if new_file ~= sound_file then
        stop_player()
        sound_file = new_file
    end

    volume_percent = new_volume
    if player ~= nil then
        obs.obs_source_set_volume(player, volume_percent / 100.0)
    end
end

function script_load(settings)
    obs.obs_frontend_add_event_callback(on_event)
end

function script_unload()
    stop_player()
end
