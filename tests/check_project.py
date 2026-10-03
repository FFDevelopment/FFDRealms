#!/usr/bin/env python3
"""Dependency-free structural/data/reference-grid checks, NOT a Godot compiler.
Run: python tests/check_project.py
No user saves are read, written or deleted by this script.
"""
from __future__ import annotations
import ast
import collections
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
checks: list[dict[str, object]] = []

def check(ok: bool, name: str) -> None:
    checks.append({"check": name, "passed": bool(ok)})
    print(("PASS: " if ok else "FAIL: ") + name)


def literal(source: str, variable: str):
    """Read only a literal constant with an AST whitelist; never eval project code."""
    match = re.search(r"^const\s+" + re.escape(variable) + r"[^=\n]*=\s*", source, re.M)
    if not match:
        raise ValueError(f"Missing constant {variable}")
    return parse_expression(source[match.end():])


def parse_expression(source: str):
    # Find the shortest complete Python-compatible literal expression. The project
    # deliberately keeps catalog/layout literals in this simple data subset.
    lines = source.splitlines()
    for end in range(1, len(lines) + 1):
        text = "\n".join(lines[:end]).strip()
        try:
            node = ast.parse(text, mode="eval").body
        except SyntaxError:
            continue
        return convert(node)
    raise ValueError("Unterminated data literal")


def convert(node: ast.AST):
    if isinstance(node, ast.Name) and node.id in {"true", "false", "null"}:
        return {"true": True, "false": False, "null": None}[node.id]
    if isinstance(node, ast.Constant):
        return node.value
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
        return -convert(node.operand)
    if isinstance(node, (ast.List, ast.Tuple)):
        return [convert(x) for x in node.elts]
    if isinstance(node, ast.Dict):
        return {convert(k): convert(v) for k, v in zip(node.keys, node.values)}
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in {"Vector2", "Vector3", "Rect2"}:
        return [convert(x) for x in node.args]
    raise ValueError(f"Not a permitted data literal: {ast.dump(node)}")


def main() -> int:
    gd_files = sorted(ROOT.rglob("*.gd"))
    for file in gd_files:
        text = file.read_text(encoding="utf-8")
        for reference in re.findall(r'"(res://[^"\n]+)"', text):
            check((ROOT / reference[6:]).is_file(), f"Resource exists: {file.name} -> {reference}")
        functions = re.findall(r"^(?:static\s+)?func\s+(\w+)\s*\(", text, re.M)
        check(len(functions) == len(set(functions)), f"Unique function names: {file.name}")
        check(not any(line.startswith(" ") for line in text.splitlines() if line.strip() and not line.lstrip().startswith("#")), f"Tab indentation: {file.name}")
    # Regression guard for the 0.1.0 startup failure. These are source checks,
    # not general Godot API validation or a substitute for native compilation.
    # API: https://docs.godotengine.org/en/4.3/classes/class_environment.html
    world = (ROOT / "scripts/world.gd").read_text(encoding="utf-8")
    check(bool(re.search(
        r"^\s*settings\.reflected_light_source\s*=\s*Environment\.REFLECTION_SOURCE_DISABLED\s*$",
        world, re.M)), "Reflection setting uses the documented Environment enum")
    check(not any(re.search(r"\bEnvironment\.REFLECTED_SOURCE_\w+", f.read_text(encoding="utf-8"))
                  for f in gd_files), "No invalid Environment.REFLECTED_SOURCE_* references in GDScript")
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    check('run/main_scene="res://scenes/main.tscn"' in project, "Entry scene is configured")
    check('Game="*res://scripts/game_state.gd"' in project, "Game autoload is configured")
    check('Network="*res://scripts/network_service.gd"' in project, "Network autoload is configured")
    check('renderer/rendering_method="gl_compatibility"' in project, "Compatibility renderer is configured")
    catalog = (ROOT / "scripts/catalog.gd").read_text(encoding="utf-8")
    layout = (ROOT / "scripts/world_layout.gd").read_text(encoding="utf-8")
    items = literal(catalog, "ITEMS")
    recipes = literal(catalog, "RECIPES")
    skills = literal(catalog, "SKILLS")
    buildings = literal(layout, "BUILDINGS")
    pond = literal(layout, "POND")
    limit = literal(layout, "LIMIT")
    north = literal(layout, "NORTH_LIMIT")
    obstacles = literal(layout, "OBSTACLES")
    clearance = literal(layout, "NAV_CLEARANCE")
    radius = literal(layout, "TARGET_SOLID_RADIUS")
    solid_kinds = literal(layout, "SOLID_TARGET_KINDS")
    spawn = literal(layout, "SPAWN")
    targets_source = layout.split("static func targets()", 1)[1].split("\n\treturn ", 1)[1]
    targets = parse_expression(targets_source)
    check(len(targets) == 36, "36 interactive world targets are defined")
    check(len({t["id"] for t in targets}) == len(targets), "Target identifiers are unique")
    check(len(skills) == 6 and len(items) == 20, "6 skills and 20 item types are defined")
    for name, recipe in recipes.items():
        check(recipe["output"] in items and all(i in items for i in recipe["cost"]), f"Recipe item references: {name}")
        check(all(isinstance(n, int) and n > 0 for n in recipe["cost"].values()), f"Positive recipe costs: {name}")
        check(recipe["skill"] in skills and recipe["xp"] > 0, f"Recipe skill and XP: {name}")
    for target in targets:
        if "item" in target:
            check(target["item"] in items and target["skill"] in skills, f"Gathering references: {target['id']}")
            check(target["duration"] > 0 and target["stock"] != 0, f"Gathering timer and stock: {target['id']}")
    def in_rect(x, z, x0, z0, width, height, extra=0):
        return x0 - extra <= x < x0 + width + extra and z0 - extra <= z < z0 + height + extra
    def blocked(x, z):
        if in_rect(x, z, *pond, clearance):
            return True
        for b in buildings:
            cx, cz = b["center"]
            w, h = b["size"]
            if in_rect(x, z, cx - w/2, cz - h/2, w, h, clearance):
                return True
        if any(in_rect(x, z, *o, clearance) for o in obstacles):
            return True
        return any(t["kind"] in solid_kinds and math.hypot(x - t["pos"][0], z - t["pos"][2]) <= radius for t in targets)
    walkable = {(x,z) for x in range(-limit,limit+1) for z in range(north,limit+1) if not blocked(x,z)}
    start = (round(spawn[0]), round(spawn[2]))
    check(start in walkable, "Spawn is walkable in the reference grid")
    seen = {start}
    queue = collections.deque([start])
    while queue:
        x,z = queue.popleft()
        for dx,dz in ((1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,1),(1,-1),(-1,-1)):
            nxt = (x+dx,z+dz)
            if nxt not in walkable or nxt in seen:
                continue
            if dx and dz and ((x+dx,z) not in walkable or (x,z+dz) not in walkable):
                continue
            seen.add(nxt)
            queue.append(nxt)
    for t in targets:
        x,z=t["pos"][0],t["pos"][2]
        if t["kind"] == "fish":
            reachable=any(math.hypot(cx-min(max(cx,pond[0]),pond[0]+pond[2]),
                                     cz-min(max(cz,pond[1]),pond[1]+pond[3])) <= literal(layout,"FISHING_BANK_RANGE") for cx,cz in seen)
        else:
            reachable=any(math.hypot(cx-x,cz-z)<=2.15 for cx,cz in seen)
        check(reachable, f"Reachable interaction approach in reference grid: {t['id']}")
    check(seen == walkable, "Reference grid contains no isolated walkable islands")
    by_id = {t["id"]: t for t in targets}
    fish = by_id["fish_1"]
    bait_shop = by_id["bait_bucket"]
    check(bait_shop["kind"] == "bait_shop" and "item" not in bait_shop,
          "Bucket is a shop and cannot define a fish yield")
    check(fish["kind"] == "fish" and fish["bait_item"] == "fishing_bait",
          "Pond fish require the catalog bait item")
    check(in_rect(fish["pos"][0], fish["pos"][2], *pond), "Fish visual/cast point lies in the pond")
    check("stand_pos" not in fish, "Fish target does not hard-code one bank position")
    fishing_range=literal(layout,"FISHING_BANK_RANGE")
    inset=literal(layout,"FISHING_CAST_INSET")
    max_cast=literal(layout,"FISHING_MAX_CAST")
    def bank_ok(x,z):
        edge_x=min(max(x,pond[0]),pond[0]+pond[2])
        edge_z=min(max(z,pond[1]),pond[1]+pond[3])
        return not blocked(x,z) and (round(x),round(z)) in seen and math.hypot(x-edge_x,z-edge_z) <= fishing_range
    banks={(x,z) for x,z in seen if bank_ok(x,z)}
    check(len(banks) > 60, "Many reachable bank cells exist, not just a few fixed spots")
    for side,cells in {
        "west": [(12,z) for z in range(4,16)],
        "east": [(26,z) for z in range(4,16)],
        "north": [(x,3) for x in range(13,26)],
        "south": [(x,16) for x in range(13,26)],
        "corners": [(12,3),(26,3),(12,16),(26,16)],
    }.items():
        check(all(bank_ok(x,z) for x,z in cells), f"Every sampled {side} bank cell is clear and reachable")
    for x,z in [(11.8,11.2),(26.2,6.4),(15.4,2.8),(21.6,16.2)]:
        check(bank_ok(x,z), f"Off-grid dry shoreline sample is valid: {x}, {z}")
    valid_casts=True
    for x,z in banks:
        cast_x=min(max(x,pond[0]+inset),pond[0]+pond[2]-inset)
        cast_z=min(max(z,pond[1]+inset),pond[1]+pond[3]-inset)
        valid_casts &= in_rect(cast_x,cast_z,*pond) and math.hypot(x-cast_x,z-cast_z)<=max_cast
    check(valid_casts, "Nearest casts from all reachable bank cells lie in water within rod range")
    check(not bank_ok(19,9) and not bank_ok(13,8) and not bank_ok(0,8), "Water, unsafe edge and far-away positions are not fishing stands")
    check(not bank_ok(10,6), "Bait bucket is not a valid stand or fish source")
    check(not in_rect(bait_shop["pos"][0], bait_shop["pos"][2], *pond), "Bait bucket remains on dry land")
    check("bait_shop" in solid_kinds and "fish" not in solid_kinds, "Bucket obstacle and fishing visual have separate navigation roles")
    check(items["fishing_bait"].get("stackable") is True, "Bait is explicitly stackable")
    check(all(not i.get("stackable", False) for k,i in items.items() if k != "fishing_bait"),
          "Existing item types retain one-slot-per-unit behavior")
    check(literal(catalog, "BAIT_PRICE") == 1 and literal(catalog, "BAIT_PACKS") == [1,5,10],
          "Bait price and offered pack sizes match the requested design")
    check(items["fishing_bait"]["sell"] <= literal(catalog, "BAIT_PRICE"), "Bait has no buy/sell profit loop")
    check(literal(catalog, "BAG_CAPACITY") == 28, "Backpack capacity remains 28 slots")
    check('config/custom_user_dir_name="FFDRealms_Prototype"' in project, "Existing save directory is unchanged")
    save_code = (ROOT / "scripts/save_store.gd").read_text()
    check('const SCHEMA: int = 1' in save_code, "Save file schema remains version 1")
    main_code = (ROOT / "scripts/main.gd").read_text()
    state_code = (ROOT / "scripts/game_state.gd").read_text()
    actor_code = (ROOT / "scripts/actor.gd").read_text()
    hud_code = (ROOT / "scripts/hud.gd").read_text()
    map_code = (ROOT / "scripts/world_map.gd").read_text()
    check('target_position(id)' in state_code and '_fishing_plan' in state_code, "Simulation uses live target positions and a separate fishing plan")
    check('character["bag"] = _harvest_bag(target)' in state_code, "Catch commits the bait/fish exchange as one bag replacement")
    check('var reason: String = _harvest_error(target)' in state_code.split('func _finish_harvest',1)[1].split('func _hit_enemy',1)[0],
          "Catch completion contains a fresh bait/capacity check")
    check('not amount in Catalog.BAIT_PACKS' in state_code, "Purchase handler checks offered pack sizes")
    check('func can_add_item(' in state_code and 'Catalog.inventory_slots(after)' in state_code,
          "Inventory capacity checks use post-transaction slot usage")
    check('rod_tip = Node3D.new()' in actor_code and 'if tool_key == "rod"' in actor_code, "Actor has a rod-tip marker and fishing-specific pose")
    check('player.rod_tip.global_position' in main_code and 'fishing_float.position = cast_position' in main_code,
          "Fishing visuals connect the actor rod tip and water cast point")
    check('fishing_line.visible = fishing' in main_code and 'fishing_float.visible = fishing' in main_code,
          "Fishing visuals are hidden outside active fishing")
    check('Layout.POND.get_center()' in world and 'pick_center = Vector3(pond_center.x - root.position.x' in world,
          "Water hit area is centered over the pond, not the bucket")
    check('if nearest == "fish_1":' in map_code and 'Layout.POND.has_point' in map_code,
          "Map pond clicks remain separate from service marker interactions")
    check('Game.can_add_item("fishing_bait", amount)' in hud_code and '"buy_bait"' in hud_code,
          "Bait shop buttons use the shared purchase/capacity rules")
    check('settings.ambient_light_energy = 0.32' in world, "Ambient energy reduced from 0.55 to 0.32")
    check('sun.light_energy = 0.90' in world, "Sun energy reduced from 1.45 to 0.90")
    check('settings.tonemap_exposure = 0.95' in world, "Exposure is explicitly set below the former default")
    check('settings.fog_light_energy = 0.55' in world and 'settings.fog_density = 0.0015' in world,
          "Fog brightness and density reduced")
    check('ROUGHNESS = 0.75; SPECULAR = 0.12;' in world, "Water shader has reduced specular glare")
    check('result.metallic_specular = 0.20' in (ROOT / "scripts/geometry.gd").read_text(),
          "World materials have restrained specular highlights")
    check('sun.shadow_enabled = true' in world, "Directional shadows remain enabled")
    check(literal(catalog, "VERSION") == "0.4.0" and 'config/version="0.4.0"' in project,
          "Catalog and project versions both identify 0.4.0")
    nav_code=(ROOT / "scripts/navigation.gd").read_text()
    def function_body(code, name):
        return code.split("func "+name+"(",1)[1].split("\nfunc ",1)[0]
    action=function_body(state_code,"_update_action")
    consume=function_body(state_code,"_consume_action")
    harvest=function_body(state_code,"_finish_harvest")
    hit=function_body(state_code,"_hit_enemy")
    interaction=function_body(state_code,"request_interaction")
    cancel=function_body(state_code,"cancel_action")
    check('active_target = ""' in consume and 'pending_target = ""' in consume,
          "Single action consumes both active and pending target")
    check('if not _consume_action(id):' in harvest and 'if not _consume_action(id):' in hit,
          "Both harvesting and combat require a single-use completion")
    check('action_time = 0.0' not in action and 'while ' not in action,
          "Action tick does not reset a repeat timer or run a repeated-action loop")
    check('if active_target != id or action_time < action_duration:' in consume,
          "Duplicate or premature completion is rejected")
    check('if not accepts_interaction_click():' in interaction and
          interaction.index('if not accepts_interaction_click():') < interaction.index('cancel_action()'),
          "Busy interaction clicks are rejected before they can restart the timer")
    check('_resolving_action = true' in action and 'not _resolving_action' in state_code,
          "Reward resolution rejects reentrant interaction requests")
    check('click_may_interact = Game.accepts_interaction_click()' in main_code and
          '_handle_world_click(click_position, click_may_interact, click_force_move)' in main_code,
          "World input records click readiness before deferred physics handling")
    check('if not click.pressed:' in main_code and 'Input.is_mouse_button_pressed' not in main_code,
          "World actions use press events rather than held mouse polling")
    check('key.echo' in hud_code, "Keyboard repeat events are ignored by HUD hotkeys")
    check('"water_pos"' in main_code and '"water_pos"' in map_code and '"water_pos"' in state_code,
          "World and map clicks both carry pond coordinates into the same simulation")
    check('Game.fishing_cast_position()' in main_code, "Rod float follows the per-action cast point")
    check('if can_fish_from(from):' in nav_code and '"stand_pos": from' in nav_code,
          "Fishing keeps exact nearby bank position")
    check('grid.get_point_path(start, Vector2i(x, z))' in nav_code and 'if trial.is_empty():' in nav_code,
          "Far casts select a reachable dry bank through navigation")
    check('Layout.is_pond_point(water)' in interaction and 'not requested_water is Vector3' in interaction,
          "Simulation validates water intent type and pond bounds")
    check('navigation.can_fish_from(here)' in state_code and 'Layout.FISHING_MAX_CAST + 0.15' in state_code,
          "Active fishing revalidates bank and cast range")
    check('_update_enemy_retaliation(step)' in state_code and 'EnemyAI.step' in state_code,
          "Enemy retaliation has a separate simulation update")
    check('attack_time' not in cancel and 'aggro' not in cancel,
          "Canceling a player action cannot reset enemy retaliation")
    retaliation=function_body(state_code,"_update_enemy_retaliation")
    check('_hit_enemy' not in retaliation and '_finish_harvest' not in retaliation,
          "Enemy retaliation never produces player attacks or harvests")
    check('action_progress' in actor_code and 'sin(phase * 1.8)' not in actor_code,
          "Player swing is tied to one action timeline instead of cycling")
    check('click again' in hud_code.lower() and 'one action' in hud_code.lower(),
          "In-game instructions describe the manual action rule")
    test_code=(ROOT / "tests/test_runner.gd").read_text()
    check('func _test_shoreline()' in test_code and 'func _test_manual_actions()' in test_code,
          "Native regression suite includes shoreline and single-action tests (execution separate)")
    network_code=(ROOT / "scripts/network_service.gd").read_text()
    save_code=(ROOT / "scripts/save_store.gd").read_text()
    check('func profile_summary(slot: int)' in save_code and 'data.get("name", "Adventurer")' in save_code,
          "Adventure slot labels read the saved character name")
    check('Existing adventures always restore their saved character name' in state_code,
          "Existing slot loading ignores the menu name field")
    check('func show_account_gate()' in hud_code and 'Remember this login on this computer' in hud_code,
          "Account gate includes sign-in and remember-session UX")
    check('stores a session token instead' in hud_code and 'password' not in network_code.split('func _save_or_clear_session()',1)[1],
          "Client session persistence does not write a password")
    check('func join_multiplayer()' in network_code and 'WebSocketPeer.new()' in network_code,
          "Authenticated WebSocket multiplayer presence client exists")
    check('remote_players' in network_code and '_update_remote_actors' in main_code,
          "Remote player presence is rendered in the game world")
    check((ROOT / "server/server.py").is_file() and (ROOT / "server/requirements.txt").is_file(),
          "Test account/multiplayer backend is packaged")
    check((ROOT / "docs/ROADMAP.md").is_file(), "Game advancement roadmap is packaged")

    report = {
        "scope": "Structural, catalog and reference-grid validation; not native Godot execution",
        "passed": sum(bool(x["passed"]) for x in checks),
        "failed": sum(not x["passed"] for x in checks),
        "checks": checks,
    }
    (ROOT / "docs/static_check_results.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"\nSTRUCTURAL RESULT: {report['passed']} passed, {report['failed']} failed")
    return 1 if report["failed"] else 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, KeyError) as exc:
        print(f"VALIDATION ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
