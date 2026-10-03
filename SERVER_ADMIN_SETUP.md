# FFDRealms Server & Admin Setup

## Local development server

Open `server/Start Test Server.bat`.

The backend uses the `FFDREALMS_ADMIN_KEY` environment variable for the admin dashboard key.

For a quick local-only test, `Start Test Server.bat` may provide a development fallback. Before any internet-facing deployment, use an environment variable and do not commit the real key.

### Windows environment variable

1. Open **Edit the system environment variables**.
2. Click **Environment Variables**.
3. Under **User variables**, create:
   - Name: `FFDREALMS_ADMIN_KEY`
   - Value: a long random private key
4. Restart Command Prompt/PowerShell windows.
5. Start `server/Start Test Server.bat` again.

### Temporary Command Prompt value

```bat
set FFDREALMS_ADMIN_KEY=YOUR-PRIVATE-KEY
cd server
Start Test Server.bat
```

### Temporary PowerShell value

```powershell
$env:FFDREALMS_ADMIN_KEY="YOUR-PRIVATE-KEY"
cd server
.\Start Test Server.bat
```

## Dashboard

Local development URL:

`http://127.0.0.1:8765/admin?key=YOUR_ADMIN_KEY`

Never publish screenshots or logs containing the real key.

## LAN multiplayer test

`127.0.0.1` means the current computer only.

To connect another PC on the same LAN:

1. Run `ipconfig` on the server PC.
2. Find its active IPv4 address, for example `192.168.1.50`.
3. Point the client server URL to `http://192.168.1.50:8765` using the actual address.
4. Allow the backend through Windows Firewall only on the intended private network.

## Database

Development data is stored in:

`server/ffdrealms.sqlite3`

Back it up before destructive backend changes. Do not commit production/user databases to GitHub.

## Before public hosting

At minimum add:
- HTTPS and secure WebSockets where applicable
- proper domain/reverse proxy
- secret management
- stronger admin authentication
- login/register rate limits
- password recovery
- email verification/unsubscribe flow
- automatic database backups
- logs/monitoring
- moderation/admin tools
- privacy/account deletion support
- server-authoritative gameplay progression
