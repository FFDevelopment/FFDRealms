# FFDRealms v0.4.0 — Accounts & Multiplayer Presence Test

This build keeps the v0.3.0 terrain/textures/combat and adds saved slot-name handling, development accounts, optional update-email consent, a multiplayer presence test and an admin analytics dashboard.

## New online test

Read `docs/ONLINE_TEST.md` before testing multiplayer. For local testing, run `server/Start Test Server.bat`, then launch the game. You can still choose **Play offline / local profiles**.

## Adventure name fix

Each slot now reads and displays the character name stored in that slot. Continuing an existing slot ignores the name-entry field; the field is used only when creating or replacing an adventure.

## Roadmap

See `docs/ROADMAP.md` for the recommended order from this presence test through server-authoritative progression, social systems, new skills, world expansion and public beta.

---

# FFDRealms v0.3.0 — Living Terrain

An update to the actual v0.2.3 Godot project. This is source, not an exported Windows executable or the earlier concept-art image.

## Install and keep your character

1. Stop the old project/game. Back up the existing FFDRealms save folder.
2. Extract this complete ZIP into a NEW folder. Do not copy only world.gd, and do not mix versions.
3. Import this folder's `project.godot` in your existing Godot 4 editor. The code continues to target the project's 4.3 API baseline; there is no requirement to downgrade your working editor.
4. Wait for resource and texture imports to complete, then press F5.
5. Continue your existing profile slot. The custom user directory remains `FFDRealms_Prototype`, and the profile schema remains 1. No character reset is intended.

On Windows the normal save location for this project is `%APPDATA%\FFDRealms_Prototype\profiles`. Godot's Project > Open User Data Folder is the safest way to locate the active folder. Copy the entire profiles folder, including `.bak` files, before testing or rolling back.

Save coordinates remain horizontal X/Z coordinates. The game samples current terrain height rather than storing elevation in your save. Existing location validation still chooses a nearby valid grid cell on load. Items, coins, skill XP, quests and appearance use the unchanged save rules.

`Launch Game.bat` can launch through your existing Godot executable. The project does not include Godot itself.

## What's new

- Real 3D hills and slopes, a raised northern region, woodland undulations, an elevated mining ridge, and a recessed pond basin.
- A triangle-mesh ground collider instead of the old flat box. Mouse clicks now hit that surface rather than an invisible Y=0 plane.
- Roads, stone areas and grass blended into the ground itself. No flat path slabs hovering over hills.
- Terrain-height placement for characters, creatures, buildings, resources, lamps, signs, click markers and combat popups.
- Enemy strike warnings conform to the slopes but keep their original direction, reach, timing and hit rules.
- A terrain-colored map with relief shading, one-metre contours, region/elevation hover information, paths, stone paving, water, building roofs, live markers and safe-town outlines.

The approved world texture images and reduced lighting are retained. This is NOT a replacement with the detailed models from the earlier concept image.

## First playtest

Walk from the village square north through the old watch to Northreach Camp, then toward Ironroot and the Watchwarden courtyard. You should climb gradually; town service areas and the courtyard remain level. Open M along the route and compare the ground colors, paths and contours with the world. Hover empty ground to see its region and elevation.

Check one resource on a hill, dodge one enemy strike on a slope, and fish from each pond bank. Feet, targets, warning sectors and fishing floats should stay attached to the appropriate surface. A Shift + left-click still forces movement. One click still permits only one attack, chop, mining action or cast.

## Controls retained

- Left-click: move or approach a target and perform one action.
- Shift + left-click: force movement even over an enemy's click box.
- Q / E or middle/right mouse drag: rotate the camera. Wheel: zoom.
- M: map. C: appearance in a safe town. I: backpack. J: journal.
- F: eat cooked trout. Space: cancel your action. Escape: close/pause.
- F5 or Save: save the current character in-game.

Stopping your own attacks does not stop enemy retaliation. Move out of the orange committed strike before impact. Safe-town boundaries and return-home behavior are unchanged.

## Tests and limits

Run `Run Tests.bat` and select your Godot executable to run native import, simulation, combat, appearance, texture, terrain-raycast and scene/UI checks. Output is written to `test-results.log`. The suites disable normal character saving; explicit save tests use their separate test directory.

The build was checked here with offline source, asset, grammar and independent geometry/navigation reference checks. **Native Godot compilation, gameplay, rendered appearance and performance were not run here.** Do not treat source checks as engine acceptance.

This remains a single-player prototype with ground-following X/Z navigation. It adds genuine elevation to the current region, not jumping, climbing, swimming, caves, multiple walkable floors, a terrain editor, new quests or multiplayer.

See `docs/TERRAIN_UPDATE.md` and `docs/TESTING.md` for details.
