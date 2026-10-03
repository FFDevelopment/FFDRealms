# v0.4.0 account, analytics and multiplayer test

## What this build tests

The online mode is deliberately a **presence test**, not an authoritative MMO yet. Signed-in players can see each other's saved character name, appearance, position, facing direction and join/leave state.

Inventory, coins, XP, quests, enemies and resources remain local in v0.4.0. Do not use this build as a public economy server.

## Start the local backend on Windows

1. Install Python 3 if needed.
2. Open `server/Start Test Server.bat`.
3. The first run creates a local virtual environment and installs `aiohttp` and `argon2-cffi`.
4. Keep the server window open.
5. Start FFDRealms. Create a test account or sign in.

The default client URL is `http://127.0.0.1:8765`.

## Test with two clients on one PC

Run two Godot game instances. Sign in with two different accounts, load an adventure in each, choose **Join multiplayer presence test**, then resume. Each client should see the other player's name, appearance and movement.

## Test across two computers on your LAN

On the computer running the backend, find its LAN address, for example `192.168.1.50`. In each game project's `project.godot`, set:

`network/server_url="http://192.168.1.50:8765"`

Allow TCP port 8765 through the server computer's firewall for the private network. Both machines then connect to that address.

## Admin dashboard

The development launcher sets a local default admin key for convenience. Open the URL printed by the server window. The dashboard reports:

- unique installs (random local install ID; no hardware fingerprint)
- total game opens
- accounts
- logins
- multiplayer sessions
- currently connected players
- recorded multiplayer minutes
- update-email opt-ins
- recent account usernames and supplied email addresses

For anything reachable from the public internet, replace the default admin key with a long random secret and do not expose this raw HTTP development server directly.

## Account security in this prototype

- Passwords are hashed server-side with Argon2 and are not written to the game save.
- The client never stores the password. "Remember me" stores a random server session token.
- Account data is stored in `server/ffdrealms.sqlite3`.
- The update-email checkbox is explicit opt-in.
- v0.4.0 records email consent but does **not** send email. A production mail provider and unsubscribe/verification flow should be added before public update campaigns.

## Internet deployment is a later step

For public testing, put the service behind HTTPS/WSS using a real domain and reverse proxy, move secrets to environment variables, enable backups, add rate limiting and account recovery, and review privacy/terms obligations before collecting real user information.
