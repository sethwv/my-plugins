fix: client matching for multi-server setups and live_proxy compatibility

Fixes two issues: client matching logic now correctly scopes session identifiers per media server, preventing cross-server mismatches in setups with multiple servers sharing identifiers. Also updates the Dispatcharr proxy import to try `live_proxy` first with a fallback to `ts_proxy` for older installs.
