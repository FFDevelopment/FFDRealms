from __future__ import annotations

import asyncio
import hashlib
import html
import json
import os
import re
import secrets
import sqlite3
import time
from pathlib import Path
from typing import Any

from aiohttp import WSMsgType, web
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError, VerificationError

ROOT = Path(__file__).resolve().parent
DB_PATH = Path(os.environ.get("FFDREALMS_DB", ROOT / "ffdrealms.sqlite3"))
HOST = os.environ.get("FFDREALMS_HOST", "0.0.0.0")
PORT = int(os.environ.get("FFDREALMS_PORT", "8765"))
ADMIN_KEY = os.environ.get("FFDREALMS_ADMIN_KEY", "")
SESSION_TTL = 60 * 60 * 24 * 7
WORLD_X_LIMIT = 63.0
WORLD_Z_MIN = -62.0
WORLD_Z_MAX = 62.0
MAX_SPEED = 12.0  # generous network validation ceiling; game walk speed is lower.
USERNAME_RE = re.compile(r"^[A-Za-z0-9_]{3,24}$")
EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
PH = PasswordHasher(time_cost=2, memory_cost=32768, parallelism=2)


def now() -> int:
    return int(time.time())


def db() -> sqlite3.Connection:
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA foreign_keys=ON")
    return con


def init_db() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with db() as con:
        con.executescript(
            """
            CREATE TABLE IF NOT EXISTS accounts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL UNIQUE COLLATE NOCASE,
                password_hash TEXT NOT NULL,
                email TEXT,
                updates_opt_in INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL,
                last_login_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS sessions (
                token_hash TEXT PRIMARY KEY,
                account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                created_at INTEGER NOT NULL,
                expires_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS opens (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                install_id TEXT NOT NULL,
                build TEXT NOT NULL,
                opened_at INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_opens_install ON opens(install_id);
            CREATE TABLE IF NOT EXISTS login_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                logged_in_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS play_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                character_name TEXT NOT NULL,
                started_at INTEGER NOT NULL,
                ended_at INTEGER,
                duration_seconds INTEGER NOT NULL DEFAULT 0
            );
            """
        )


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def account_for_token(token: str) -> sqlite3.Row | None:
    if not token:
        return None
    h = token_hash(token)
    with db() as con:
        row = con.execute(
            """SELECT a.* FROM sessions s JOIN accounts a ON a.id=s.account_id
               WHERE s.token_hash=? AND s.expires_at>?""",
            (h, now()),
        ).fetchone()
        if row is None:
            con.execute("DELETE FROM sessions WHERE token_hash=?", (h,))
        return row


def make_session(account_id: int) -> str:
    token = secrets.token_urlsafe(32)
    stamp = now()
    with db() as con:
        con.execute("DELETE FROM sessions WHERE expires_at<=?", (stamp,))
        con.execute(
            "INSERT INTO sessions(token_hash,account_id,created_at,expires_at) VALUES(?,?,?,?)",
            (token_hash(token), account_id, stamp, stamp + SESSION_TTL),
        )
    return token


async def json_body(request: web.Request) -> dict[str, Any]:
    try:
        data = await request.json()
    except Exception:
        raise web.HTTPBadRequest(text=json.dumps({"ok": False, "error": "Invalid JSON."}), content_type="application/json")
    if not isinstance(data, dict):
        raise web.HTTPBadRequest(text=json.dumps({"ok": False, "error": "JSON object required."}), content_type="application/json")
    return data


def response(**payload: Any) -> web.Response:
    return web.json_response(payload)


async def health(_: web.Request) -> web.Response:
    return response(ok=True, service="FFDRealms test server", build="0.4.0", active_players=len(ACTIVE))



async def me(request: web.Request) -> web.Response:
    token = request.headers.get("Authorization", "").removeprefix("Bearer ").strip()
    if not token:
        token = request.query.get("token", "")
    account = account_for_token(token)
    if account is None:
        return response(ok=False, error="Session expired.")
    return response(ok=True, username=str(account["username"]), email=str(account["email"] or ""), updates_opt_in=bool(account["updates_opt_in"]))

async def opened(request: web.Request) -> web.Response:
    data = await json_body(request)
    install_id = str(data.get("install_id", ""))[:80]
    build = str(data.get("build", "unknown"))[:32]
    if len(install_id) < 8:
        return response(ok=False, error="Invalid install id.")
    with db() as con:
        con.execute("INSERT INTO opens(install_id,build,opened_at) VALUES(?,?,?)", (install_id, build, now()))
    return response(ok=True)


async def register(request: web.Request) -> web.Response:
    data = await json_body(request)
    username = str(data.get("username", "")).strip()
    password = str(data.get("password", ""))
    email = str(data.get("email", "")).strip().lower()
    opt_in = bool(data.get("updates_opt_in", False))
    if not USERNAME_RE.fullmatch(username):
        return response(ok=False, error="Username must be 3-24 letters, numbers or underscores.")
    if len(password) < 8 or len(password) > 128:
        return response(ok=False, error="Password must be 8-128 characters.")
    if email and not EMAIL_RE.fullmatch(email):
        return response(ok=False, error="Enter a valid email or leave it blank.")
    if opt_in and not email:
        return response(ok=False, error="Email is required to receive update notices.")
    password_hash = PH.hash(password)
    stamp = now()
    try:
        with db() as con:
            cur = con.execute(
                "INSERT INTO accounts(username,password_hash,email,updates_opt_in,created_at,last_login_at) VALUES(?,?,?,?,?,?)",
                (username, password_hash, email or None, 1 if opt_in else 0, stamp, stamp),
            )
            account_id = int(cur.lastrowid)
            con.execute("INSERT INTO login_events(account_id,logged_in_at) VALUES(?,?)", (account_id, stamp))
    except sqlite3.IntegrityError:
        return response(ok=False, error="That username is already taken.")
    token = make_session(account_id)
    return response(ok=True, token=token, username=username, email=email, updates_opt_in=opt_in)


async def login(request: web.Request) -> web.Response:
    data = await json_body(request)
    username = str(data.get("username", "")).strip()
    password = str(data.get("password", ""))
    with db() as con:
        row = con.execute("SELECT * FROM accounts WHERE username=? COLLATE NOCASE", (username,)).fetchone()
    if row is None:
        await asyncio.sleep(0.15)
        return response(ok=False, error="Invalid username or password.")
    try:
        PH.verify(str(row["password_hash"]), password)
    except (VerifyMismatchError, VerificationError):
        await asyncio.sleep(0.15)
        return response(ok=False, error="Invalid username or password.")
    stamp = now()
    with db() as con:
        con.execute("UPDATE accounts SET last_login_at=? WHERE id=?", (stamp, int(row["id"])))
        con.execute("INSERT INTO login_events(account_id,logged_in_at) VALUES(?,?)", (int(row["id"]), stamp))
    token = make_session(int(row["id"]))
    return response(
        ok=True,
        token=token,
        username=str(row["username"]),
        email=str(row["email"] or ""),
        updates_opt_in=bool(row["updates_opt_in"]),
    )


async def logout(request: web.Request) -> web.Response:
    data = await json_body(request)
    token = str(data.get("token", ""))
    if token:
        with db() as con:
            con.execute("DELETE FROM sessions WHERE token_hash=?", (token_hash(token),))
    return response(ok=True)


async def update_subscription(request: web.Request) -> web.Response:
    data = await json_body(request)
    token = str(data.get("token", ""))
    account = account_for_token(token)
    if account is None:
        return response(ok=False, error="Session expired. Sign in again.")
    email = str(data.get("email", "")).strip().lower()
    opt_in = bool(data.get("updates_opt_in", False))
    if email and not EMAIL_RE.fullmatch(email):
        return response(ok=False, error="Enter a valid email or leave it blank.")
    if opt_in and not email:
        return response(ok=False, error="Email is required to receive update notices.")
    with db() as con:
        con.execute("UPDATE accounts SET email=?, updates_opt_in=? WHERE id=?", (email or None, 1 if opt_in else 0, int(account["id"])))
    return response(ok=True, email=email, updates_opt_in=opt_in)


ACTIVE: dict[int, dict[str, Any]] = {}
NEXT_PLAYER_ID = 1
ACTIVE_LOCK = asyncio.Lock()


def clean_appearance(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        return {}
    allowed = {
        "skin_color", "hair_color", "eyes_color", "shirt_color", "pants_color", "shoes_color",
        "belt_color", "pack_color", "stitch_color", "hair_style", "shirt_fabric", "pants_style",
        "pants_fabric", "shoe_style", "shoe_fabric", "pack_visible",
    }
    clean: dict[str, Any] = {}
    for key in allowed:
        if key in value:
            raw = value[key]
            if isinstance(raw, (str, bool, int, float)):
                clean[key] = raw
    return clean


def public_players() -> list[dict[str, Any]]:
    return [
        {
            "id": p["id"], "name": p["name"], "x": p["x"], "z": p["z"],
            "fx": p["fx"], "fz": p["fz"], "appearance": p["appearance"],
        }
        for p in ACTIVE.values()
    ]


async def broadcast(payload: dict[str, Any]) -> None:
    text = json.dumps(payload, separators=(",", ":"))
    dead: list[int] = []
    for pid, player in list(ACTIVE.items()):
        ws: web.WebSocketResponse = player["ws"]
        if ws.closed:
            dead.append(pid)
            continue
        try:
            await ws.send_str(text)
        except Exception:
            dead.append(pid)
    for pid in dead:
        ACTIVE.pop(pid, None)


async def websocket_handler(request: web.Request) -> web.StreamResponse:
    global NEXT_PLAYER_ID
    token = request.query.get("token", "")
    account = account_for_token(token)
    if account is None:
        raise web.HTTPUnauthorized(text="Authentication required")
    ws = web.WebSocketResponse(heartbeat=20.0, max_msg_size=32768)
    await ws.prepare(request)
    async with ACTIVE_LOCK:
        pid = NEXT_PLAYER_ID
        NEXT_PLAYER_ID += 1
        ACTIVE[pid] = {
            "id": pid, "account_id": int(account["id"]), "username": str(account["username"]),
            "name": str(account["username"]), "x": 0.0, "z": 8.0, "fx": 0.0, "fz": -1.0,
            "appearance": {}, "ws": ws, "last_update": time.monotonic(), "state_seen": False, "session_row": None,
        }
    await ws.send_json({"type": "welcome", "id": pid, "players": public_players()})
    await broadcast({"type": "players", "players": public_players()})
    try:
        async for msg in ws:
            if msg.type != WSMsgType.TEXT:
                if msg.type in (WSMsgType.ERROR, WSMsgType.CLOSE, WSMsgType.CLOSED):
                    break
                continue
            try:
                data = json.loads(msg.data)
            except json.JSONDecodeError:
                continue
            if not isinstance(data, dict):
                continue
            kind = str(data.get("type", ""))
            player = ACTIVE.get(pid)
            if player is None:
                break
            if kind == "hello":
                name = str(data.get("name", account["username"])).replace("\n", " ").strip()[:16]
                if not name:
                    name = str(account["username"])
                player["name"] = name
                player["appearance"] = clean_appearance(data.get("appearance", {}))
                with db() as con:
                    cur = con.execute(
                        "INSERT INTO play_sessions(account_id,character_name,started_at) VALUES(?,?,?)",
                        (int(account["id"]), name, now()),
                    )
                    player["session_row"] = int(cur.lastrowid)
            elif kind == "state":
                stamp = time.monotonic()
                x = float(data.get("x", player["x"]))
                z = float(data.get("z", player["z"]))
                fx = float(data.get("fx", player["fx"]))
                fz = float(data.get("fz", player["fz"]))
                if not (-WORLD_X_LIMIT <= x <= WORLD_X_LIMIT and WORLD_Z_MIN <= z <= WORLD_Z_MAX):
                    continue
                elapsed = max(0.05, stamp - float(player["last_update"]))
                dist = ((x - float(player["x"])) ** 2 + (z - float(player["z"])) ** 2) ** 0.5
                # The first packet may jump from the placeholder spawn to a legitimate saved position.
                if player.get("state_seen", False) and dist / elapsed > MAX_SPEED and elapsed < 2.0:
                    continue
                player["x"], player["z"] = x, z
                player["fx"], player["fz"] = max(-1.0, min(1.0, fx)), max(-1.0, min(1.0, fz))
                player["last_update"] = stamp
                player["state_seen"] = True
            elif kind == "appearance":
                player["appearance"] = clean_appearance(data.get("appearance", {}))
            elif kind == "ping":
                await ws.send_json({"type": "pong", "t": data.get("t", 0)})
            await broadcast({"type": "players", "players": public_players()})
    finally:
        async with ACTIVE_LOCK:
            player = ACTIVE.pop(pid, None)
        if player and player.get("session_row"):
            with db() as con:
                row = con.execute("SELECT started_at FROM play_sessions WHERE id=?", (int(player["session_row"]),)).fetchone()
                if row:
                    end = now()
                    con.execute(
                        "UPDATE play_sessions SET ended_at=?, duration_seconds=? WHERE id=?",
                        (end, max(0, end - int(row["started_at"])), int(player["session_row"])),
                    )
        await broadcast({"type": "players", "players": public_players()})
    return ws


def require_admin(request: web.Request) -> None:
    supplied = request.query.get("key", "") or request.headers.get("X-Admin-Key", "")
    if not ADMIN_KEY or not secrets.compare_digest(supplied, ADMIN_KEY):
        raise web.HTTPUnauthorized(text="Set FFDREALMS_ADMIN_KEY on the server, then open /admin?key=YOUR_KEY")


async def admin(request: web.Request) -> web.Response:
    require_admin(request)
    with db() as con:
        accounts = int(con.execute("SELECT COUNT(*) FROM accounts").fetchone()[0])
        optins = int(con.execute("SELECT COUNT(*) FROM accounts WHERE updates_opt_in=1").fetchone()[0])
        installs = int(con.execute("SELECT COUNT(DISTINCT install_id) FROM opens").fetchone()[0])
        opens_count = int(con.execute("SELECT COUNT(*) FROM opens").fetchone()[0])
        logins = int(con.execute("SELECT COUNT(*) FROM login_events").fetchone()[0])
        sessions = int(con.execute("SELECT COUNT(*) FROM play_sessions").fetchone()[0])
        seconds = int(con.execute("SELECT COALESCE(SUM(duration_seconds),0) FROM play_sessions").fetchone()[0])
        users = con.execute(
            "SELECT username,email,updates_opt_in,created_at,last_login_at FROM accounts ORDER BY id DESC LIMIT 50"
        ).fetchall()
    rows = "".join(
        f"<tr><td>{html.escape(str(u['username']))}</td><td>{html.escape(str(u['email'] or ''))}</td>"
        f"<td>{'Yes' if u['updates_opt_in'] else 'No'}</td><td>{time.strftime('%Y-%m-%d %H:%M', time.localtime(u['created_at']))}</td>"
        f"<td>{time.strftime('%Y-%m-%d %H:%M', time.localtime(u['last_login_at'])) if u['last_login_at'] else ''}</td></tr>"
        for u in users
    )
    body = f"""<!doctype html><html><head><meta charset='utf-8'><title>FFDRealms Admin</title>
<style>body{{font-family:system-ui;background:#10201a;color:#e8e2ce;margin:0;padding:24px}}h1{{color:#dcc187}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px}}.card{{background:#1e342c;border:1px solid #53634c;border-radius:10px;padding:16px}}.n{{font-size:30px;color:#f2d58f}}table{{width:100%;border-collapse:collapse;margin-top:24px;background:#182a24}}td,th{{padding:10px;border-bottom:1px solid #33483e;text-align:left}}small{{color:#9fb1a6}}</style></head><body>
<h1>FFDRealms Test Dashboard</h1><small>Development analytics only. Refresh for current values. Active player presence is in memory and resets when the server restarts.</small>
<div class='grid'>
<div class='card'><div class='n'>{installs}</div>Unique installs</div><div class='card'><div class='n'>{opens_count}</div>Game opens</div>
<div class='card'><div class='n'>{accounts}</div>Accounts</div><div class='card'><div class='n'>{logins}</div>Logins</div>
<div class='card'><div class='n'>{sessions}</div>MP sessions</div><div class='card'><div class='n'>{len(ACTIVE)}</div>Players online now</div>
<div class='card'><div class='n'>{seconds // 60}</div>Recorded play minutes</div><div class='card'><div class='n'>{optins}</div>Email update opt-ins</div>
</div>
<h2>Recent accounts</h2><table><tr><th>Username</th><th>Email</th><th>Updates</th><th>Created</th><th>Last login</th></tr>{rows}</table>
</body></html>"""
    return web.Response(text=body, content_type="text/html")


async def admin_json(request: web.Request) -> web.Response:
    require_admin(request)
    with db() as con:
        stats = {
            "unique_installs": int(con.execute("SELECT COUNT(DISTINCT install_id) FROM opens").fetchone()[0]),
            "game_opens": int(con.execute("SELECT COUNT(*) FROM opens").fetchone()[0]),
            "accounts": int(con.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]),
            "email_opt_ins": int(con.execute("SELECT COUNT(*) FROM accounts WHERE updates_opt_in=1").fetchone()[0]),
            "logins": int(con.execute("SELECT COUNT(*) FROM login_events").fetchone()[0]),
            "multiplayer_sessions": int(con.execute("SELECT COUNT(*) FROM play_sessions").fetchone()[0]),
            "recorded_play_seconds": int(con.execute("SELECT COALESCE(SUM(duration_seconds),0) FROM play_sessions").fetchone()[0]),
            "players_online": len(ACTIVE),
        }
    return response(ok=True, **stats)


def create_app() -> web.Application:
    init_db()
    app = web.Application(client_max_size=64 * 1024)
    app.add_routes([
        web.get("/api/health", health),
        web.get("/api/me", me),
        web.post("/api/open", opened),
        web.post("/api/register", register),
        web.post("/api/login", login),
        web.post("/api/logout", logout),
        web.post("/api/subscription", update_subscription),
        web.get("/ws", websocket_handler),
        web.get("/admin", admin),
        web.get("/admin/stats.json", admin_json),
    ])
    return app


if __name__ == "__main__":
    print(f"FFDRealms test server: http://127.0.0.1:{PORT}")
    print("Set FFDREALMS_ADMIN_KEY before starting to enable the admin dashboard.")
    web.run_app(create_app(), host=HOST, port=PORT, print=None)
