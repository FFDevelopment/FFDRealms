from __future__ import annotations
import asyncio
import importlib.util
import os
import tempfile
from pathlib import Path

from aiohttp.test_utils import TestClient, TestServer


def load_backend(db_path: str):
    os.environ["FFDREALMS_DB"] = db_path
    os.environ["FFDREALMS_ADMIN_KEY"] = "backend-test-key"
    spec = importlib.util.spec_from_file_location("ffdrealms_backend", Path(__file__).with_name("server.py"))
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(module)
    return module


async def run() -> None:
    with tempfile.TemporaryDirectory(prefix="ffdrealms_backend_test_") as td:
        backend = load_backend(str(Path(td) / "test.sqlite3"))
        server = TestServer(backend.create_app())
        client = TestClient(server)
        await client.start_server()
        try:
            health = await (await client.get("/api/health")).json()
            assert health["ok"]
            await client.post("/api/open", json={"install_id": "install-alpha-123456", "build": "0.4.0"})
            async def register(name: str):
                response = await client.post("/api/register", json={
                    "username": name, "password": "test-password-123", "email": name.lower()+"@example.test", "updates_opt_in": True
                })
                data = await response.json()
                assert data["ok"], data
                return data["token"]
            token_a, token_b = await register("AlphaTester"), await register("BetaTester")
            me = await (await client.get("/api/me", headers={"Authorization": "Bearer " + token_a})).json()
            assert me["ok"] and me["username"] == "AlphaTester"
            ws_a = await client.ws_connect("/ws?token=" + token_a)
            ws_b = await client.ws_connect("/ws?token=" + token_b)
            welcome_a = await ws_a.receive_json()
            welcome_b = await ws_b.receive_json()
            assert welcome_a["type"] == "welcome" and welcome_b["type"] == "welcome"
            await ws_a.send_json({"type": "hello", "name": "Alice", "appearance": {"pants_style": "jeans"}})
            await ws_b.send_json({"type": "hello", "name": "Bob", "appearance": {"pants_style": "slacks"}})
            await ws_a.send_json({"type": "state", "x": 10.0, "z": 12.0, "fx": 1.0, "fz": 0.0})
            await asyncio.sleep(0.05)
            assert len(backend.ACTIVE) == 2
            assert any(p["name"] == "Alice" and abs(p["x"] - 10.0) < 0.01 for p in backend.ACTIVE.values())
            stats = await (await client.get("/admin/stats.json?key=backend-test-key")).json()
            assert stats["ok"] and stats["accounts"] == 2 and stats["players_online"] == 2
            await ws_a.close()
            await ws_b.close()
            await asyncio.sleep(0.05)
            assert len(backend.ACTIVE) == 0
            print("BACKEND PASS: auth, email opt-in, sessions, two WebSocket players, position update, analytics and disconnect cleanup")
        finally:
            await client.close()


if __name__ == "__main__":
    asyncio.run(run())
