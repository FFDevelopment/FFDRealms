# FFDRealms 0.2.3 — World texture pass

This is an update to the actual Godot project, based on FFDRealms 0.2.2. It is not a concept screenshot, a new map, or a replacement game. The earlier generated concept image is not a screenshot of this release and is not bundled as a game asset.

## What changes on screen

- Ground: mottled grass, rough earth, small pebbles in paths, irregular stone paving in the village square and ruins, and textured dig/quarry surfaces.
- Buildings: mottled plaster, coursed masonry, roof shingles, timber grain, plank doors and textured chimneys/foundations. Existing roof colors are retained.
- Trees and resources: bark grooves, leaf detail, cracked rocks and mineral texture on the existing individually colored ore pieces.
- Props: wooden bank chests, dock planks, the bait bucket, woven market canopies, stone forges and brushed-metal anvil surfaces.
- Creatures: soft fur on wolves, rough stone on crawlers and the Watchwarden, and moss detail on mosslings. Their eyes and emissive indicators stay separate.
- Pond: two slowly scrolling ripple layers, subtle normal detail and a lighter shallow-water edge. Water remains opaque and subdued; no bright reflection/refraction effect was added.

The pass uses **18 original, tileable 512 × 512 material families**, each with a neutral color map and a surface-normal map: **36 PNGs**. Existing mesh colors tint the maps; they are not replaced with a single shared color. Normal maps add small lighting details without changing geometry, collision or silhouette.

This does not replace the current low-poly models, redesign the buildings, add scenery from the mockup or change the camera/HUD. The model silhouettes and layouts remain the prototype's existing ones. A texture pass alone will not make the game identical to the earlier concept image.

## Preserved systems

Combat and movement timing, proximity engagement, committed strike sectors, town exclusions, patrol/return-home rules, one-click interactions, pond-bank fishing, inventory, prices, recipes, XP, quests, saves, wardrobe dyes and garment materials are unchanged. The lower sunlight, ambient lighting, fog and exposure settings are unchanged. Attack warning materials are deliberately excluded from texturing.

The new materials never mutate the shared plain-material cache or per-character garment materials. Static terrain uses world-scale mapping. Building props and moving enemies use local mapping so textures move with their meshes. Material/texture references are shared and cached; no new textures are generated in the gameplay frame loop.

## Install

Back up your saves and stop the old game. Extract the complete archive into a new folder, import its `project.godot` using your existing Godot 4 editor, and let the asset import finish before F5. Continue your existing character slot. No save migration/reset is required by this update.

Do not copy only `world.gd`. Keep `assets/`, `shaders/`, `scripts/`, `scenes/` and `project.godot` together. Imported `.ctex` caches are not shipped; the editor rebuilds them from the PNGs and their included `.import` settings. The ZIP is source, not an engine or Windows executable.

## Troubleshooting and comparison

The project contains two appearance-only settings at the bottom of `project.godot`:

```ini
[ffdrealms]
visuals/world_textures=true
visuals/normal_maps=true
```

Restart the game after a change. Set `visuals/normal_maps=false` to keep the new color textures without their normal detail. Set `visuals/world_textures=false` to use the previous flat-color world materials and original water shader. These are project settings, not in-game wardrobe choices; neither alters saved progress.

Disabling world textures does not stop the imported resources from being loaded, so it is a rendering/material comparison fallback, not a promise of reduced memory use. Frame rate and memory have not been measured.

## First in-game acceptance check

Continue in Hearthmere. Look at the square paving, lodge wall/roof, a bank chest, a tree and an ore node. Move/rotate/zoom to check texture scale, seams, flicker and glare. Visit the pond from each bank and cast once. Check the dock, bait bucket, water motion and bobber placement.

At the wardrobe, change top/trouser colors and switch jeans/slacks. Then approach one mossling, let it engage, attack once and dodge its orange sector. Check that its surface texture moves with its body and that the warning stays clearly visible. Retreat into each safe town, then visit Northreach's camp, quarry and guardian courtyard. Finally save/reload and confirm the same character appearance/progress.

## Verification boundary

The packaged maps were inspected as texture swatches, and source/asset/reference checks were run. **Godot import/compilation, GPU shader compilation, rendered gameplay, performance and Windows launchers have not been run in the build environment.** A Godot binary was unavailable and download attempts did not produce one. Material-swatch inspection is not an in-game screenshot or rendered scene review.

`Run Tests.bat` includes a new native `texture_runner.gd` suite alongside all previous suites. It checks texture resources, material assignment, unchanged collision shapes, cache isolation, wardrobe protection and the fallback modes. These native tests are included but not reported as executed here. See `TESTING.md` for actual executed results.
