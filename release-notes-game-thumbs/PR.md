v1.8.0 - Generic event support, new soccer leagues, font registry, disk caching

Adds support for generating covers and thumbnails for non-matchup league events (e.g. races) via new `title`, `subtitle`, and `iconurl` query parameters, along with a font registry and bundled Saira Stencil fonts. Includes two new soccer leagues (US Open Cup, USL Championship), an `ALLOW_EVENT_OVERLAYS` environment flag, and a switch from in-memory to filesystem-backed image caching.
