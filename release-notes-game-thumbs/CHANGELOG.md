## [v1.8.0] - Unreleased

### Added
- Generic league event cover and thumbnail support with optional `title`, `subtitle`, and `iconurl` query parameters for non-matchup events (e.g. motorsports races) - #116 by @brheinfelder
- Custom font support with a font registry system and bundled Saira Stencil fonts (OFL v1.1)
- Docker mount support for custom fonts
- US Open Cup (`usa.open`) and USL Championship (`usa.usl.1`) leagues - #118 by @trevorswanson
- `ALLOW_EVENT_OVERLAYS` environment flag to gate event overlay rendering
- Filesystem-backed image caching replacing in-memory caches

### Fixed
- Critical fix for HockeyTech API key extraction - older versions of game-thumbs may fail to retrieve data without this update
- Improved error handling and logging for team-not-found cases

### Security
- canvas updated to 3.2.3 (integer overflow fix in image data operations)
- axios updated to 1.15.0 (proxy handling and header injection vulnerabilities)
