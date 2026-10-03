# FFDRealms advancement roadmap

This roadmap keeps the project playable at every milestone. The order matters: networking, persistence and security come before a large content expansion.

## Phase 1 — Foundation (current through v0.4.x)

- Preserve one-click-per-action gathering and combat.
- Stable terrain, map relief, appearance customization, safe towns and enemy AI.
- Fix adventure-slot identity so a saved character keeps its own name.
- Test accounts, remembered sessions, optional update-email consent and basic analytics.
- Multiplayer presence test: authenticated players can see names, appearance, movement and join/leave state.
- Do **not** trust the client for XP, coins, loot, inventory or quest completion yet.

Exit gate: two or more clients can connect/reconnect without profile corruption, duplicate remote avatars or stale sessions.

## Phase 2 — Authoritative multiplayer core (v0.5.x)

- Move player position validation, health, combat hits, gathering rewards, resource stock, enemy state and cooldowns to the server.
- Move character inventory, equipment, skills, coins, quests and bank persistence to server-owned saves.
- Character selection becomes account-owned rather than device-owned.
- Server-side action rate limits preserve the anti-AFK/manual-click design.
- Shared enemy targeting, loot ownership rules and resource contention.
- Reconnect recovery and server snapshots.

Exit gate: disconnecting, reconnecting or modifying the client cannot duplicate items, XP or coins.

## Phase 3 — Social world (v0.6.x)

- Local / area chat, friends, ignore list and moderation tools.
- Player examine panel and visible equipment.
- Safe player-to-player trade with a two-step confirmation and server transaction log.
- Party system for PvE, shared objective credit and configurable loot rules.
- World population display and server status.

Exit gate: trading, chat and parties survive reconnects and cannot bypass inventory limits.

## Phase 4 — Skills and economy expansion (v0.7.x)

- Add Farming, Crafting, Fletching and possibly Magic/Ranged progression.
- Tool tiers and meaningful gathering speed/quality progression without passive AFK farming.
- More ores, trees, fish, cooking recipes, armor and weapon tiers.
- NPC shop stock / price rules and money sinks.
- Item metadata and database IDs designed for later marketplace support.

Exit gate: each new skill feeds at least two other systems instead of existing as an isolated XP bar.

## Phase 5 — World expansion (v0.8.x)

- Second major town with its own architecture, economy and quest line.
- Multi-level dungeon or cave instance.
- More terrain biomes: forest, mountain, marsh or coast.
- Travel network that must be unlocked through gameplay.
- Stronger boss encounter requiring movement/dodge mechanics rather than stat checks alone.

Exit gate: the world has a clear early-game route, mid-game route and repeatable reasons to revisit old areas.

## Phase 6 — Production services (v0.9.x)

- HTTPS/WSS deployment behind a production reverse proxy.
- Proper domain, backups, migrations, monitoring and rate limits.
- Password reset / email verification provider.
- Admin roles, bans, mutes and account support tooling.
- Privacy policy, terms, email unsubscribe flow and retention controls before public collection of real user data.
- Telemetry events with explicit definitions so analytics remain useful rather than becoming raw event noise.

Exit gate: server restores from backup, account recovery works, and admin actions are auditable.

## Phase 7 — Public beta / 1.0

- Installer/export pipeline, patch notes and version compatibility checks.
- Performance budget and load tests with realistic concurrent players.
- Tutorial polish, accessibility and key rebinding.
- Final art pass replacing procedural placeholders where needed.
- Content cadence: quests, regions, equipment, enemies and seasonal events.

## Recommended next build after v0.4.0

Build **v0.5.0 — Server Authority Test** before adding another large map. Start with a small authoritative slice: movement validation, one tree, one ore node, one enemy, one item reward, inventory and XP. Once that survives disconnect/reconnect and deliberate client tampering, migrate the rest of the current systems to the server.
