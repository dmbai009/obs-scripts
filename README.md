<div align="center">

# OBS Studio Lua Scripts

Two small utilities for **OBS Studio**: a sound notification after saving a replay and timestamp markers for streams or recordings.

[Русский](README.ru.md) · [MIT License](LICENSE)

</div>

## Scripts

| Script | Purpose | Extra requirements |
| --- | --- | --- |
| [`replay_save_sound.lua`](replay_save_sound.lua) | Play a chosen notification sound when OBS saves a Replay Buffer clip | None |
| [`timestamp.lua`](timestamp.lua) | Save timestamp markers with a hotkey, optional offset and stream-title-based filenames | `yt-dlp.exe` for automatic stream title lookup on Windows only |

Both are regular **Lua scripts** loaded through OBS's built-in scripting interface; they are **not** native plugins or separate applications.

## Installation

1. Download the script you need from this repository.
2. Open OBS Studio → **Tools → Scripts**.
3. Click **+** and select the `.lua` file.
4. Select the script in the list to configure it.

No additional Lua installation is required. Keep the script file in place after adding it to OBS.

## Replay Save Sound

[`replay_save_sound.lua`](replay_save_sound.lua) plays a short audio notification when OBS reports that a Replay Buffer clip has been saved.

- Choose a sound file (WAV, MP3, OGG, FLAC and other formats supported by the OBS Media Source).
- Set notification volume from **0 to 100%**.
- Use **Проверить звук** (*Test sound*) to preview it.
- The script creates a private OBS Media Source; it does not add anything to your Scenes/Sources list.
- Sound is sent to the configured OBS monitoring device, **not directly to the OBS output audio tracks**.

**Important:** If OBS is also capturing the system/desktop audio from that monitoring device, the notification **can still be heard in the recording or stream** through desktop-audio capture. To choose the monitoring device, open **Settings → Audio → Advanced → Monitoring Device**.

Requires Replay Buffer to be enabled and running in OBS. The script uses the `OBS_FRONTEND_EVENT_REPLAY_BUFFER_SAVED` event; it does not play when saving a normal recording.

## Timestamp

[`timestamp.lua`](timestamp.lua) writes a timestamp to a text file when you press a configured OBS hotkey while streaming or recording.

### Setup

1. Add the Lua script in **Tools → Scripts**.
2. Set **Смещение времени** (*Time offset*, in seconds). The default is **−30 seconds**.
3. Choose **Папка для таймкодов** (*Output folder*). The default is your Desktop folder.
4. Choose a filename mode:
   - **Automatic:** retrieve the live stream title from a provided stream/channel URL with `yt-dlp.exe` (Windows, while streaming).
   - **Manual:** use the provided custom title.
   - **Date only:** use `stream_timestamps` as the filename prefix.
5. Open **Settings → Hotkeys** and assign a key to **Сохранить таймкод** (*Save timestamp*).

Each press appends one line, such as:

```text
00:12:34
00:28:07
01:03:51
```

Files are named `<title>_YYYY-MM-DD_HH-MM-SS.txt` using the session start time. Filenames are cleaned of characters invalid on Windows. Repeated key presses within **500 ms** are ignored. The selected offset is applied to the elapsed stream/recording time and the result is clamped to zero. If OBS is both streaming and recording, streaming time is used.

### Automatic stream titles (Windows)

- Download `yt-dlp.exe` from the [official yt-dlp releases](https://github.com/yt-dlp/yt-dlp/releases) and select its path in the script settings, or place it next to the Lua script, or make it available on `PATH`.
- Supply the stream or channel URL in **Ссылка на канал или эфир**.
- The script uses `yt-dlp` for **metadata lookup only**; it does **not** download the video.
- Title lookup runs asynchronously, with limited retries. Once a title is found, the timestamp file is renamed to match it.
- If lookup fails or is not configured, timestamps are still saved with the configured manual fallback title (or `stream_timestamps`).
- The automatic lookup feature depends on whether `yt-dlp` supports the provided website and URL. It is Windows-specific; manual/date naming works without it.

## Notes

- The settings and control labels inside both scripts are in Russian.
- OBS scripting and media APIs can change across releases. The scripts require OBS Studio with Lua scripting support; compatibility with every OBS version has not been verified.
- These scripts are not affiliated with the OBS Project.
- No credentials or channel information are built into the published scripts. For `timestamp.lua`, your channel URL is entered locally in OBS settings.

## License

MIT © 2026 **dmbai009**. See [LICENSE](LICENSE).
