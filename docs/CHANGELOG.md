# Changelog

## 0.4.0 — Accounts & Multiplayer Presence Test

- Adventure slot selector now reads each slot's saved character name. Continuing a saved slot ignores the menu name field.
- Added development account sign-in and registration UI with remembered session tokens; passwords are not stored by the game client.
- Added optional email-update consent and account settings. This build records consent but does not send email.
- Added authenticated WebSocket multiplayer presence: remote character name, appearance, position, facing, join and leave state. Progression remains local until the authoritative-server milestone.
- Added Python/aiohttp development backend with Argon2 password hashing and SQLite persistence.
- Added admin analytics dashboard for unique installs, opens, accounts, logins, multiplayer sessions, online players, recorded play time and email opt-ins.
- Added development roadmap through authoritative multiplayer, social systems, skill/economy expansion, world expansion and production services.
- v0.3.0 terrain, textures, anti-AFK manual actions, dodge combat and safe-town behavior are preserved.

# v0.3.0 — Living Terrain

- Replaced flat ground and collider with authored 3D terrain and a matching triangle collider.
- Added rolling woodland, raised northern terraces/mining ridge, smoother routes and a recessed pond.
- Blended existing grass/path/stone/paving textures into the slopes; removed old flat overlays.
- Grounded player, enemies, props, camera, markers and effects; projected committed strike warnings.
- Replaced flat map fills with matching terrain colors, relief, contours, region/elevation hover and retained live markers.
- Kept gameplay/AI/safe zones/save format/appearance and original texture assets intact.
- Added offline geometry/navigation reference checks and native terrain/click-map-warning tests.
- Native engine execution and visual acceptance were not performed in the build environment.

---

# Changelog

## 0.2.3 — World texture pass

Base: supplied FFDRealms 0.2.2 source archive.

- Added 36 original, pre-baked 512px albedo/normal PNGs and reproducible texture-authoring code.
- Assigned explicit, cached materials to terrain, paving, buildings, trees, resources, props and creature bodies. Retained existing tints and geometry.
- Added restrained textured pond water with layered ripples and shallow-edge coloring; kept the old water as a fallback.
- Added appearance-only project toggles for world textures and normal maps. Retained existing clothing fabric/dye materials, softer lighting, combat indicators and all gameplay/save logic.
- Added import/pixel/source checks, a baseline geometry/behavior contract, negative regression controls and a native texture/material suite in Run Tests.bat.
- Source/asset checks executed. Native Godot compilation, GPU rendering, performance and manual gameplay remain untested here.

## 0.2.2 — Committed strikes, movement dodges and proximity engagement

Base: supplied FFDRealms 0.2.1 source archive.

- Locked enemy strike position, facing and geometry at windup; current-position sector/cover checks at impact replace the tracking full-radius hit.
- Added per-species windup/recovery/arc tuning, fixed directional warning sectors, countdowns and one-time miss/engagement feedback.
- Added mossling proximity engagement; retained/verified LOS-gated frontier detection and all town, return-home and dead-state gates.
- Split the player strike (0.35 s) from the minimum start-to-start cadence (0.95 s). Moving can cancel an unlanded strike but cannot refund the cooldown. No repeat attacks or queued clicks.
- Added Shift + left-click force-move and direct, validated ground segments for responsive repositioning.
- Preserved customization, safe-town footprints, navigation exclusion, progression, economy, pond fishing and reduced lighting. No saved-field/schema changes.
- Added source/reference combat checks, native dodge/proximity/visual regressions, and updated the local Windows test runner. Engine execution and visual playtesting were not available in the build environment.

## 0.2.1 — Character appearance and safe-town exclusion

Base: the supplied 0.2.0 Northreach source archive.

- Added nine individual dye channels: skin, hair, eyes, top, trousers, footwear, belt, backpack and stitching.
- Added fabric/style selections, jeans pockets/seams, slacks creases, boots/shoes and three hair choices.
- Added original cached neutral weave maps, per-actor dye materials and a separate live 3D wardrobe preview.
- Added C/top-bar/backpack/menu access, new-character prompt, Save/Discard/reset-preview behavior and in-panel error feedback.
- Added allowlisted per-profile cosmetics with legacy defaults, opaque colors and write-before-commit persistence. No economy, XP, inventory or weapon bonuses.
- Retained existing enemy return-home/attack behavior; added an enemy-only navigation grid, inclusive town edges, exact segment exclusion and per-substep movement guards.
- Applied town exclusion to spawn/respawn, patrol, chase, sidestep, backing away, return and crowd recovery. Added a final damage guard and invalid-position repair.
- Marked safe towns on the HUD/map. Retained the existing safe-area extents, quests, items, softened daylight, full-shore fishing and manual one-click actions.
- Added offline appearance/reference checks, a native appearance/safety suite and wardrobe/main-scene smoke checks. Updated existing static checks for the version and stronger line-of-sight helper.
- Native Godot import/execution, rendering and Windows/manual playtesting were not run in the build environment.


## 0.2.0 — Northreach and moving encounters

Base: the supplied FFDRealms 0.1.3 source archive.

### Combat

- Added a separate enemy state-machine module with idle roaming, pursuit, windup, recovery, lateral repositioning and return-home states.
- Added live enemy positions and facing; rendering, pick boxes, map markers, player approach and damage validation now use those positions.
- Added body spacing, obstacle-aware pursuit, cover checks, bounded path recalculation and stuck/return recovery.
- Added safe-area and home-radius disengagement. Returning enemies are protected and regain health at home, not in the middle of pursuit.
- Added simple procedural walk/hop, lunge and flinch presentation plus attack-warning rings and live health/status labels.
- Kept one-click/one-action player behavior. No automatic counterattack, stored click queue or AFK repeat was introduced.
- Existing clicks can pursue a moving target for at most 12 seconds and authorize only one swing. A ground click or Space cancels the player's action, not enemy combat.
- Generalized species health, speed, reach, damage, windup, detection, leash, drops, XP, coins and respawn timing.

### Expansion

- Extended the map north to -67 while keeping existing coordinates and other boundaries.
- Opened a clear north-road gate and added navigation/map/visual source-of-truth wall footprints.
- Added Northreach Camp, Briarwood, Ironroot Dig and the open-air Watchwarden courtyard.
- Added 18 new interactive targets: 5 services, 8 gathering nodes and 5 enemies. Total: 36 targets.
- Added briar wolves, stone crawlers and the Watchwarden with distinct original procedural silhouettes.
- Added coal, steel bars, steel swords, wolf pelts, living stone shards and Watchwarden cores. Total: 20 item types.
- Added the Beyond the Old Watch expedition, journal and dialogue panels, one-time reward and steel-recipe unlock.
- Added two steel recipes requiring Smithing 5 plus expedition completion.
- Added shared-bank camp services and map walking shortcuts; no fast-travel teleportation.

### Compatibility and validation

- Added expedition save fields with defaults for 0.1.x saves. Kept original schema, save directory, items and starter-quest IDs.
- Retained bait purchase, fishing from all reachable banks, transactional catches, and softened lighting.
- Updated existing source/native tests to use expanded bounds and moving positions rather than obsolete counts or fixed-spawn assumptions.
- Added frontier source/reference checks and a separate native frontier regression suite.
- Source, data, reference navigation and grammar checks were executed; native Godot and manual/rendered tests were not executed in the build environment.

## Earlier releases

0.1.3 introduced manual one-click actions and full-shore fishing. 0.1.2 introduced bait purchases, pond fishing and lower lighting. 0.1.1 corrected the Environment enum spelling. Historical check reports are retained under `docs/history/` and do not certify this release.
