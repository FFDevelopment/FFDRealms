# FFDRealms

FFDRealms is an original Godot-based fantasy RPG prototype developed by FFDevelopment.

Current development focus:
- skill-based gathering and progression
- click-to-move combat with dodgeable enemy attacks
- safe towns and roaming enemies
- terrain, map relief, and world texturing
- character appearance customization
- account/login foundation
- multiplayer presence testing
- server/admin analytics foundation

## Current version

Development baseline: **v0.4.0**

## Run the game

1. Install Godot 4.x.
2. Import `project.godot`.
3. Press **F5** to run the project.

## Development server

The test backend lives in `server/`.

See:
- `server/README.md`
- `SERVER_ADMIN_SETUP.md`
- `docs/ROADMAP.md`

The v0.4.x network test synchronizes authenticated player presence, character names, appearance, position, facing, and join/leave state. Inventory, XP, coins, quests, gathering rewards, and combat rewards are not yet server-authoritative.

## Release channels

The repository reserves three update channels:
- `development`
- `beta`
- `stable`

Their manifests live in `manifests/`.

Standalone PC builds can eventually consume these manifests through the FFDRealms launcher. Steam, Google Play, and Apple builds should use their platform-native update systems.

## Platforms

Primary targets:
- Windows
- Linux
- macOS
- Android
- iOS

Console support is a later platform-certification phase.
