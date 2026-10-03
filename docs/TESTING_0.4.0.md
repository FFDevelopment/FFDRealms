# FFDRealms v0.4.0 testing record

## Completed in the build environment

- Structural/data/reference-grid checks: **357 passed, 0 failed**.
- Northreach/frontier reference checks: **100 passed, 0 failed**.
- Character appearance / safe-town reference checks: **82 passed, 0 failed**.
- Dodge/proximity combat reference checks: **99 passed, 0 failed**.
- Texture/import/source invariants: **253 passed, 0 failed**.
- Terrain/reference geometry checks: **116 passed, 0 failed**.
- GDScript grammar parser: **28 files passed, 0 failed**.
- Python backend bytecode compilation: passed.
- Backend end-to-end test: passed registration, Argon2 login, remembered-token endpoint, email opt-in, two simultaneous WebSocket players, player state update, admin analytics and disconnect cleanup using an isolated temporary SQLite database.

## Not completed here

No Godot executable is installed in this environment, so native Godot compilation, API/type checking, scene initialization, rendered remote players, Windows launchers and manual two-client gameplay were **not run** here.

Run `Run Tests.bat` on the development PC for the Godot suites. Run `server/Test Backend.bat` after the server virtual environment has been installed for the backend suite.

## Multiplayer scope

v0.4.0 intentionally synchronizes player presence only. Inventory, XP, coins, quests, gathering, combat rewards and enemy/resource authority are still local. This prevents the presence experiment from being mistaken for a secure public multiplayer economy.
