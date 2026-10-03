# FFDRealms v0.3.0 testing record

## Completed in the build environment

The packaged offline checks validate source invariants, resource references, texture pixels/import settings, deterministic data, save/appearance preservation and independent geometry/navigation models. The GDScript grammar check is separate; it does not resolve engine APIs or compile the game.

Current machine-readable results are in:

- `static_check_results.json`, `frontier_check_results.json`, `appearance_check_results.json`, `combat_check_results.json` and `texture_check_results.json`.
- `terrain_check_results.json`: authored samples, triangle-diagonal consistency, layout/asset hashes, quarter-metre dry-land slope scan, connected navigation, resource approaches, bank access and ground/map/warning integrations.
- `grammar_check_results.json`: parsed GDScript files, source hashes and negative syntax controls.
- `build_verification.json`: clean-extraction results and deterministic terrain rebake comparison.

The old texture-only promise of unchanged flat ground geometry is intentionally superseded. Current tests still protect the unmodified gameplay, AI, safety, save, wardrobe and creature model code, while explicitly checking the terrain changes. Historical `texture_base_contract.json` hashes are retained rather than relabeled as the new geometry.

## NOT RUN in the build environment

**Native Godot compilation/import, all native game/terrain/scene suites, GPU shader execution, rendered visuals, manual gameplay, Windows launchers and performance measurement.** No usable Godot executable was available; an attempted official binary download did not produce one. Source and reference checks must not be represented as native test passes.

## Run the native checks on your PC

Stop the game, double-click `Run Tests.bat`, and choose your Godot executable. It imports the project and runs:

1. Existing progression, navigation, inventory, one-action gathering, fishing, crafting, combat and save regression suite.
2. Northreach/enemy movement suite.
3. Appearance and protected town boundary suite.
4. Committed-strike/dodging/proximity engagement suite.
5. Imported texture/material isolation and matching terrain-collision fallback suite.
6. New terrain resource, mesh, physics raycast, map alignment, bank access and sloped-warning suite.
7. Main scene/HUD initialization suite.

The runner stops on reported failures and writes `test-results.log`. Native tests disable normal profile saving; explicit file tests use `user://test_profiles`. Back up real saves before all update testing regardless.

The native terrain suite compares the visible mesh and collider faces, shoots downward physics rays at landmarks and target anchors, compares hits with the height sampler, verifies map coordinate round trips and checks a sloped wolf warning against the actual ground. These tests are bundled but were not executed here.

## Manual acceptance route

Use an existing character. Walk from the village square through the old watch to Northreach Camp, Ironroot and the Watchwarden courtyard. Rotate/zoom while moving. Check ground click accuracy uphill and downhill, feet/props on the surface, signs above the terrain and the absence of floating path slabs.

Open M and compare paths, grass, forest, stone and water with the terrain. Check contour relief, hover labels/elevation, player/enemy markers and map click destinations. Safe-town outlines must not hide land colors.

Provoke an enemy on a slope. Let one orange warning complete while standing inside it, then evade a second strike. The warning must remain attached to the land without changing its X/Z reach or homing toward the player. Retreat into a town and confirm the enemy stays outside and returns home. The player must never counterattack without a new click.

Fish on all four sides and the corners. Check rod/line/float position, bait accounting and one-cast stopping. Test one elevated tree/ore node. Save, close, reopen and verify character progression and appearance.

Reject the build for player/target sinking, above-ground click displacement, a missing ground surface, floating strike warnings, unintended repeat actions, safe-zone intrusion, unreadable texture/lighting changes or persistent engine errors. A successful source check is not a waiver for those failures.
