# FFDRealms development backend

`server.py` provides the v0.4.0 development account service, WebSocket presence server and admin analytics dashboard.

## Local start

Windows: run `Start Test Server.bat`.

macOS/Linux: run `./Start Test Server.sh`.

Default port: `8765`.

Set these environment variables when needed:

- `FFDREALMS_ADMIN_KEY` — admin dashboard secret. Required for `/admin`.
- `FFDREALMS_PORT` — server port.
- `FFDREALMS_HOST` — bind address; defaults to `0.0.0.0`.
- `FFDREALMS_DB` — alternate SQLite path.

Do not expose the development server directly to the public internet. See `../docs/ONLINE_TEST.md`.
