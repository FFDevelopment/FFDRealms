# FFDRealms Server & Admin Setup

## Local development server

Open `server/Start Test Server.bat`.

The backend uses the `FFDREALMS_ADMIN_KEY` environment variable for the admin dashboard key.

For a quick local-only test, the BAT file may provide a development fallback. Before any internet-facing deployment, use an environment variable and do not commit the real key.

### Windows environment variable

1. Open **Edit the system environment variables**.
2. Click **Environment Variables**.
3. Under **User variables**, create:
   - Name: `FFDREALMS_ADMIN_KEY`
   - Value: a long random private key
4. Restart Command Prompt/PowerShell windows.
5. Start `server/Start Test Server.bat` again.

### Dashboard

Local development URL:

`http://127.0.0.1:8765/admin?key=YOUR_ADMIN_KEY`

Never publish screenshots or logs containing the real key.

## LAN multiplayer test

`127.0.0.1` means the current computer only. Use the server PC's LAN IPv4 address for another PC on the same network.

## Database

Development data is stored in:

`server/ffdrealms.sqlite3`

Back it up before destructive backend changes. Do not commit production/user databases to GitHub.

## Before public hosting

Add HTTPS/WSS where applicable, proper secret management, stronger admin authentication, login/register rate limits, password recovery, email verification/unsubscribe, automatic backups, logs/monitoring, moderation tools, privacy/account deletion support, and server-authoritative gameplay progression.
