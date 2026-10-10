<div align="center">

# OBS Studio Lua Scripts

**Two lightweight tools for OBS Studio:** a sound notification after saving a replay and hotkey-based timestamp markers for streams or recordings.

[MIT License](LICENSE)

</div>

## Scripts

| Script | What it does | Requirements |
| --- | --- | --- |
| [`replay_save_sound.lua`](replay_save_sound.lua) | Plays a selected sound after OBS saves a Replay Buffer clip | OBS Studio with Lua scripting support |
| [`timestamp.lua`](timestamp.lua) | Appends timestamp markers to a text file using an OBS hotkey, with configurable offset and filenames | OBS Studio with Lua scripting support; optional `yt-dlp.exe` for automatic live-stream titles on Windows |

Both are **Lua scripts** for OBS Studio's built-in scripting system, not native plugins or standalone applications.

## Installation

1. Download the `.lua` script you want to use.
2. In OBS Studio, open **Tools → Scripts**.
3. Click **+** and select the downloaded `.lua` file.
4. Select the script in the list to configure its settings.

No separate Lua installation is required. Keep the Lua file at the same location after adding it to OBS.

## Replay Save Sound

[`replay_save_sound.lua`](replay_save_sound.lua) plays a notification when OBS reports that a Replay Buffer clip has been saved.

1. In **Tools → Scripts**, choose the script.
2. Select a **Sound File** (WAV, MP3, OGG, FLAC, or another format supported by OBS's Media Source).
3. Set the **Volume** (0–100%).
4. Click **Test Sound** to preview the notification.

The script uses a private OBS Media Source. It does **not** create a visible entry in your Scenes or Sources list. Audio is sent to the **OBS monitoring device**, not directly into the recording or streaming audio tracks.

> [!IMPORTANT]
> If OBS also captures desktop audio from the same monitoring device, the notification **may be included in your stream or recording** through desktop-audio capture. Configure the device under **Settings → Audio → Advanced → Monitoring Device**.

The Replay Buffer must be enabled and running. This script reacts to **saved replay clips**, not the completion of a regular recording.

## Timestamp

[`timestamp.lua`](timestamp.lua) appends elapsed-time markers to a `.txt` file when you press a configured OBS hotkey during a live stream or recording.

### Setup

1. Add the script via **Tools → Scripts**.
2. Set **Time Offset (seconds)**. Default: **−30**.
3. Choose a **Timestamp Output Folder**. Default: your Desktop.
4. Select a **Filename Mode**:
   - **Automatic from Stream URL (yt-dlp):** retrieve a live stream title with `yt-dlp.exe` (Windows, while streaming).
   - **Manual Title:** use the text entered in **Title / Fallback Title**.
   - **Date Only:** use `stream_timestamps` as the filename prefix.
5. Under **Settings → Hotkeys**, assign a shortcut to **Save Timestamp**.

Example output:

```text
00:12:34
00:28:07
01:03:51
```

Files use the pattern `<title>_YYYY-MM-DD_HH-MM-SS.txt`, based on the session start time. Invalid Windows filename characters are removed, and presses within **500 ms** of a successful save are ignored. The offset is added to the elapsed time and negative results are clamped to zero. When OBS is both streaming and recording, the **streaming elapsed time** takes precedence.

### Automatic stream titles (Windows)

1. Download [`yt-dlp.exe` from the official releases](https://github.com/yt-dlp/yt-dlp/releases).
2. Set **yt-dlp.exe (automatic mode, Windows)** to the executable path, place it alongside `timestamp.lua`, or add it to `PATH`.
3. Enter a supported stream or channel URL in **Stream or Channel URL (automatic mode)**.
4. Choose **Automatic from Stream URL (yt-dlp)** in **Filename Mode**.

The script requests **metadata only**; it does not download video. Lookup runs in the background with limited retries. When the title becomes available, the existing timestamp file is renamed to use it.

If the title cannot be retrieved, the script still saves timestamps under the fallback title or `stream_timestamps`. Site support depends on `yt-dlp` and the supplied URL. Manual and date-only naming work without `yt-dlp`, including on non-Windows systems.

## Compatibility and limitations

- Scripts have **English** descriptions, settings and hotkey labels.
- Tested OBS versions are not exhaustively documented; behavior may vary across OBS releases and operating systems.
- Automatic stream-title lookup in `timestamp.lua` is implemented for Windows only and requires `yt-dlp.exe`.
- OBS hotkey registration IDs and script setting keys are preserved when translating the interface, so existing configurations are intended to remain compatible.
- No channel URL, account credential or personal filesystem path is embedded in the scripts. Configure those locally in OBS.
- These community scripts are not affiliated with the OBS Project.

## License

Distributed under the [MIT License](LICENSE). Copyright © 2026 **dmbai009**.
