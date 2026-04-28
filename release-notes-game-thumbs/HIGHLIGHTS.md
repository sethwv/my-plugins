**game-thumbs v1.8.0**

- Generic event covers and thumbnails: pass `title`, `subtitle`, and `iconurl` params to generate league art for non-matchup events like races - contributed by @brheinfelder
- Custom font support with a built-in Saira Stencil font and a Docker mount for your own fonts
- Two new soccer leagues: US Open Cup and USL Championship - contributed by @trevorswanson
- Event overlays can now be toggled via the `ALLOW_EVENT_OVERLAYS` environment flag
- Image cache now persists to disk instead of memory
- Critical fix for HockeyTech API key extraction - older versions may stop working without this update
