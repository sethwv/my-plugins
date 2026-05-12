fix: compatibility with live_proxy rename in new Dispatcharr versions

Dispatcharr renamed its internal `ts_proxy` module to `live_proxy`, which caused the plugin to fail on load. The import now tries `live_proxy` first and falls back to `ts_proxy`, and the Redis key prefix is set accordingly, so the plugin works on both old and new Dispatcharr installs.
