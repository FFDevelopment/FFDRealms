# v0.3.0 terrain architecture addendum

The notes below describe earlier foundations. In v0.3.0, ground is no longer a flat box or Y=0 click plane. `terrain_data.gd` / `hearthmere_heightfield.tres` provide authored samples; `terrain.gd` provides exact triangle-height sampling and slope tests; `terrain_mesh.gd` builds the mesh and matching collider. World material masks and the relief map share that bake.

Authority/saves deliberately remain logical X/Z with Y=0. Grounding is applied at the world presentation boundary, and mouse collision hits are normalized back to logical coordinates. No foot height is saved. Enemy action validation remains horizontal and its warning mesh is draped over the same surface. This does not create multi-storey or jumping support.

See TERRAIN_UPDATE.md for the current complete terrain design and TESTING.md for verification limits.

---

# Architecture — FFDRealms 0.2.2

## Ownership

`game_state.gd` remains the local simulation owner. UI actions call `dispatch()` with intent, never reward totals. This is **single-player**, not an authenticated server or completed networking layer.

`enemy_ai.gd` operates on per-enemy runtime dictionaries and returns at most one validated enemy damage event per step. It cannot grant player XP/items or create player actions. `game_state.gd` applies returned damage and handles player recovery. Player kill rewards remain exclusively in `_hit_enemy()`, after consuming the single-use action and marking the target dead.

`world_layout.gd` owns stable target IDs, spawn definitions, pond bounds, buildings, new wall footprints, map bounds and safe areas. Target definitions are not mutated to represent movement. `world[id].pos` is live enemy state; `target_position(id)` is the shared accessor. Non-moving targets fall back to their definition position.

`navigation.gd` caches static rectangles and solid target centres when building its AStarGrid2D. Player routing retains that grid. A second enemy-only grid also marks the existing safe-town rectangles, expanded by `ENEMY_SAFE_MARGIN`, as blocked. Enemy route points and every movement substep pass an exact closed segment/rectangle test as well as terrain checks. Continuous segment samples supplement cell checks for enemy movement and melee cover. These are grid/segment checks, not full CharacterBody3D physics or dynamic navmesh avoidance.

## Enemy lifecycle

- **Idle / patrol:** passive roaming near home. All current enemy definitions have a short, line-of-sight-gated notice radius. Default notice is 3.5 m; an explicit notice of zero remains a future passive-species opt-out.
- **Chase:** bounded repathing toward the opponent, turn-to-face, body spacing, and a preferred melee distance.
- **Windup:** snapshot origin, facing, reach, arc and duration. Hold both position and facing. At impact, test the current player position against the committed sector and require unobstructed cover/town lines. Transition to recovery before returning damage.
- **Recover / strafe:** a brief recovery followed by a short lateral step. Flinch presentation does not reset attack timers.
- **Return:** stop attacking after a leash/safety/unreachable condition, reject player attacks, walk home and restore full HP on arrival. In a persistent crowd blockage, returning actors may pass other actors, but never static terrain or a protected town, to avoid permanent deadlocks.
- **Dead / respawn:** clear aggro/pathing, commit one reward, hide the creature and disable its pick layer. Cooldown completion resets runtime AI at the stable home point without creating a player action.

Player movement can still pass through enemy bodies; this release adds enemy spacing and world-obstacle avoidance rather than a complete mutual character-collision system. The orange sector is a fixed ground strike; only the current single player is tested. No area damage to NPCs or multiplayer victims has been introduced. Collision uses the player ground-position point, not a capsule or animation-bone hitbox.

## Player action contract

World input captures whether a click was eligible when pressed. `request_interaction` rejects busy clicks before altering timers. A pending moving-enemy target may refresh its approach route for one intended swing, with a 12-second timeout. The interaction must revalidate a legal non-safe combat cell and a clear segment to the live enemy.

At completion, `_consume_action()` clears the active and pending target before rewards. No repeat timer, counterattack or next-action queue is started. A moved target that leaves reach/cover can cancel a swing; another click is required. Pressing Stop or clicking the ground does not reset enemy timers or the player weapon cooldown. `combat_rules.gd` separates the 0.35-second strike from a 0.95-second minimum start interval. Cooldown expiry grants readiness, never another action. Movement before impact cancels that player hit; a blocked early attack click does not cancel an existing movement path.

## Expansion data and progression

The northern extension uses original coordinates. `SAFE_AREAS` identifies the village service area and camp; `OBSTACLES` feeds visible walls, map geometry and blocked navigation rectangles. The guardian area is an open-air encounter, not a separate instance or an interior.

Camp service nodes reuse existing kinds and transactions, including the shared character bank. `ranger` is the added quest panel. An additive `frontier` character dictionary tracks accepted/claimed status and capped wolf/coal/guardian milestones. Existing `quest` data remains separate, so wolves cannot count as starter mosslings.

Steel recipes use both the Smithing level and expedition-claimed flag in the simulation, not only a disabled UI button. New item IDs are normal inventory entries that use the same equip, sell, deposit, withdraw and save paths.

## Presentation

`enemy_visual.gd` builds original procedural silhouettes and animates only visual nodes. `world.gd` moves root nodes and their pick areas to the simulation positions. Labels remain readable separately from the rotating bodies. Dead enemies no longer intercept clicks.

`world_map.gd` uses aspect-preserving transforms over `MAP_BOUNDS`, follows live targets and converts clicks back into world coordinates. Walking shortcuts dispatch movement; they do not teleport. `hud.gd` handles expedition panels and tracks new quest fields in its refresh signature.

## Persistence and limits

Save schema and directory are unchanged. Missing expedition fields default to empty progress. Missing appearance fields default through the whitelist in `appearance.gd`. Runtime AI, active timers and pending action requests are not stored. Loading a character rebuilds the world at full stock/home states, as before.

Native multiplayer, macros/bot detection, armor, instanced dungeons, mobile export, performance certification and final character animation are outside this release. Primary Godot API references consulted: `AStarGrid2D`, `Vector3` and the project's existing 4.3 baseline documentation. Engine behavior must be validated with the included native suites.

## Character appearance

`appearance.gd` owns the color/style schema, defaults and sanitizer. Color inputs are exactly six hex RGB digits; alpha is not configurable. Style strings must be in a fixed allowlist; unknown properties are discarded. Only neutral `ImageTexture` resources are globally cached, not mutable colored materials.

`actor.gd` registers meshes by dye slot and owns a `StandardMaterial3D` per slot per actor. Neutral fabric maps multiply individual albedo colors. Style-specific detail groups toggle jeans pockets/seams, slacks creases, footwear and hair. Weapon/tool construction and action animation remain separate. A serialized-look signature avoids rebuilding materials each presentation frame.

`wardrobe.gd` owns a disposable validated draft and a `SubViewport` with `own_world_3d=true`. Its preview uses the same Actor class but has no direct Game mutation path. `hud.gd` submits Save through `dispatch("appearance", ...)`. The simulation checks safe-town access and validates all input again. When saving is enabled, a complete proposed snapshot is written successfully before committing the appearance in memory. Cancellation discards the preview node, not the character.

Existing profiles retain their money, items, weapons, quests and progression. Cosmetics are not armor or loot slots and do not alter stats. Only the currently selected local profile is updated.

## Boundary defense

`is_safe` includes all edges/corners. `enemy_forbidden` adds body clearance; `segment_crosses_safe` uses a closed 2D slab test rather than just checking segment endpoints. Locomotion uses the expanded footprint, while combat line-of-sight uses the actual protected footprint. Leash values and return-home rules are unchanged; strike windup/recovery timing is explicitly updated in the combat definitions. Invalid external/runtime placement is an exceptional repair path: relocate to a valid home and cancel combat before a hit can be applied. This is not a claim of bot/cheat resistance or an authoritative online server.

The native appearance test suite and main-scene smoke tests must still be run on a Godot installation. Python reference geometry results are not GDScript execution results.

## Shared combat geometry and feedback

`combat_rules.gd` provides reach, half-angle and point-in-sector validation. `enemy_ai.gd` captures these into runtime strike fields in `begin_windup()`. Facing updates are suspended during windup and recovery; hit flinches remain visual only. Each resolved strike increments `strike_id` once, allowing `game_state.gd` to emit one miss cue without awarding anything. A new windup may aim again, so one successful dodge is not permanent immunity.

`enemy_visual.gd` builds a 48-segment triangle fan and an inner arc outline once per creature. It uses the same reach/angle helpers, with an independent unshaded translucent material per instance. The warning is transformed by the saved strike origin/facing, never the player's moving position. Opacity/color vary; footprint size does not. It briefly remains visible during impact feedback. The mesh approximates the circular arc with very small chords; collision remains analytic.

Input records Shift at mouse-down. Shift-click bypasses target picking and routes through ordinary movement even when a swing is busy. Clear ground clicks use a validated direct segment and exact destination; obstacle routes retain the grid and only omit their first cell when the replacement segment is clear. Movement still has no invulnerability or teleport.


## World texture presentation boundary — 0.2.3

`world_materials.gd` owns preloaded image pairs and immutable world-material cache entries. `world.gd` and the construction section of `enemy_visual.gd` opt individual meshes into named surfaces. `geometry.gd`, actor/appearance modules, simulation, navigation, saving, callbacks, UI and all collision construction remain unchanged.

`shaders/pond_water.gdshader` is presentation only. It displaces the existing plane by its original amplitude and never requests screen/depth textures. New surface normal data changes lighting, not collision geometry. The default and fallback material modes share the same world layout and interaction areas. Runtime animation functions do not allocate/rebuild these materials.

`tests/texture_base_contract.json` stores fingerprints derived from the supplied 0.2.2 archive, not from the modified output. `check_textures.py` checks them against the updated project; `texture_runner.gd` provides separately pending native import/material/collider checks.
