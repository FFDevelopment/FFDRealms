# v0.3.0 — Living Terrain

## Scope

This is a source update from the actual FFDRealms 0.2.3 project. It replaces the flat ground presentation and click collider with an authored 3D heightfield and a map derived from that same field. It retains the playable map boundaries, 36 target IDs and all existing progression.

## Terrain and land materials

The authored field spans 66 by 104 metres including the outer visual margin. It uses half-metre samples: 27,797 vertices and 54,912 ground triangles, with an additional low-cost earth skirt outside the playable bounds. One static triangle collider is built from the rendered ground mesh.

Hearthmere's central service area remains near the original zero-height datum. Northreach Camp sits on a terrace approximately 2.3 metres above it, the Watchwarden courtyard is approximately 4.8 metres up, and the Ironroot mining ridge rises to roughly 7 metres. The woodland and lowlands have smaller rolling hills. These are local game coordinates, not real-world sea-level measurements.

The pond's fixed water surface is at -0.25 metres; its basin extends about 1.3 metres below that. A broad dry-bank shelf preserves fishing from all sides and corners. Water retains its existing subdued ripple material. Pond navigation remains conservative: the entire registered pond rectangle is non-walkable, including small shallow corners.

The existing grass, path, stone and cobble texture families are blended over the mesh using shared world-aligned color and layer masks. The old flat slabs are removed. Small level support areas and a smoothing pass prevent abrupt shoulders around resources and services. Every sampled dry-land slope in the reference sweep is below the 0.70 grade movement limit.

## Movement, clicking and combat

The simulation intentionally remains X/Z-based, with logical Y=0, so old saves, targeting distances, action timing and inventory rules are not reinterpreted. Visual feet and anchors sample the actual triangle height at their X/Z position. This is a ground-following 3D RPG, not a new rigid-body or jumping controller.

The height sampler uses the same A-C triangle diagonal as the mesh. It is not a separate bilinear surface, which could disagree with a triangulated ground. Ground clicks raycast the mesh collider and then pass the hit's X/Z coordinates to the existing navigation. Camera focus follows the player's physical ground height.

Enemy logic, aggression, damage, cooldowns, return-home state and safe-area layout files are byte-identical to 0.2.3. Enemy warnings now use radial subdivisions and a cached terrain projection. Only vertex heights change; their horizontal reach, sector angles and committed attack direction remain the existing hit footprint. Their materials remain untextured and unshaded for readability. This is not an expansion into multi-floor combat.

Character cosmetic geometry and materials are unchanged. The player's small ground ring tilts with the surface; there is no new foot IK or climbing animation system. Broad slopes are used to keep the existing models usable.

## Map

The 496 by 800 relief texture is baked from the exact heightfield, terrain color rules, material layers and existing tile textures. It shows grass/woodland, rocky mining ground, dirt paths, paving, shore and water colors, with elevation shading and subtle one-metre contours. The map is not a live satellite camera or a promise of pixel-identical lighting.

Building roofs, registered walls, live enemy/resource/service markers, the current route and the player remain drawn above that base. Safe areas use outlines rather than opaque fills that would hide the land. Empty-ground hover text shows the region name and sampled local elevation. Map-to-world click coordinates remain unchanged; clicking still walks, not teleports.

The base image is imported and reused, not regenerated every frame. World mesh generation happens during scene construction; warnings are only reprojected when their committed pose changes. No frame-rate claim is made without an in-engine test.

## Retained behavior

One-click gathering and attacks, no queued repeats, proximity aggression, dodgeable committed strikes, protected towns, return-home behavior, all-bank pond fishing, bait purchases/consumption, individual appearance colors/fabrics, all existing items and quests, and the reduced lighting remain in place.

No save schema or save location changes are introduced. Load-time position validation still moves an invalid position to the nearest permitted grid cell. Character resets are not required by this update; back up saves before testing or rolling back.

## Source and rebuilds

- `scripts/terrain_data.gd`: typed heightfield resource schema.
- `data/terrain/hearthmere_heightfield.tres`: committed height samples.
- `scripts/terrain.gd`: shared sampling, grounding, slope and region functions.
- `scripts/terrain_mesh.gd`: mesh, collider and material construction.
- `shaders/terrain.gdshader`: opaque terrain layer blending.
- `assets/textures/terrain/`: land tint, blend mask and relief map.
- `tools/bake_terrain.py`: deterministic offline authoring/baking tool, using Python, NumPy and Pillow. Not needed to play.
- `tests/check_terrain.py` and `tests/terrain_runner.gd`: offline reference and native engine checks respectively.

The bake records a checksum of `world_layout.gd`; changing the layout requires a review and rebake rather than letting the map silently drift from the world. No paid service, remote generation job or external model asset was used for this update.

## Not included

No additional region, new quest, equipment item, swimming, jumping, climbing, interior/cave level, terrain sculpting UI or multiplayer system is added. Those need their own gameplay and navigation work rather than being implied by a visual upgrade.
