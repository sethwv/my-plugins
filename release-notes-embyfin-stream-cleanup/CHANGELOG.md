## [v1.1.2] - 2026-05-10

### Fixed

- Client matching now correctly handles multiple media servers that share session identifiers - previously, sessions from one server could be incorrectly matched against streams from another
- Compatible with Dispatcharr versions that renamed `ts_proxy` to `live_proxy` - the plugin now tries the new module path first and falls back to the old one
