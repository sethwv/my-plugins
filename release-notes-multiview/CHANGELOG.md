## [v0.1.0] - Initial release

### Added
- Tile 2-9 Dispatcharr channel streams into a single MPEG-TS output using FFmpeg xstack; each layout appears as a standard M3U channel
- Three layout styles: Auto Grid (square-ish grid, last row centred), Featured (channel 1 large on the left, others stacked on the right), and Top Featured (channel 1 full-width on top, others in a row at the bottom)
- Classic channel selection via dropdowns and Regex selection - enter a pattern (e.g. `TSN\s*\d`) to match channels by name automatically at stream time, sorted by channel number
- Hardware encoder support: Software (libx264), NVIDIA (h264_nvenc), Intel QuickSync (h264_qsv), AMD/Intel VA-API (h264_vaapi)
- Multi-audio output: choose a single channel's audio or output one AC3 track per tile; players with multi-track support (VLC, Infuse, mpv) can switch between them. Duplicate track labels are auto-numbered (e.g. `ts1`, `ts2`, `ts3`)
- Startup placeholder: tiled black frames with channel logos and a "Starting up..." banner display immediately while FFmpeg initialises the real stream
- EPG support: generates a 14-day XMLTV feed per layout with configurable title, subtitle, and category tags; registered automatically as an EPGSource in Dispatcharr
- Configurable output resolution (1080p / 720p / 480p), max bitrate, encoder quality (CRF/CQ/global_quality), and encoder preset per global settings
- Auto-refresh interval setting to regenerate M3U and EPG on a schedule (default 24 h; 0 = manual only via Regenerate M3U button)
- Streams open through Dispatcharr's ProxyServer so connections appear in the stats view, respect stream profiles and fallback behaviour, and carry the user-agent `multiview-plugin`
- No FFmpeg processes run when nobody is watching; processes are spawned per request and killed on disconnect
