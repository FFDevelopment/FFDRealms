#!/usr/bin/env python3
"""Frontier data/source and independent navigation reference checks.
This does NOT execute GDScript or stand in for Godot compilation.
"""
from __future__ import annotations
import collections
import json
import math
from pathlib import Path
from check_project import literal, parse_expression

ROOT = Path(__file__).resolve().parents[1]
results: list[dict] = []

def check(ok: bool, name: str) -> None:
    results.append({'check': name, 'passed': bool(ok)})
    print(('PASS: ' if ok else 'FAIL: ') + name)

def body(source: str, name: str) -> str:
    return source.split('func '+name+'(', 1)[1].split('\nstatic func ',1)[0].split('\nfunc ',1)[0]

def main() -> int:
    layout = (ROOT/'scripts/world_layout.gd').read_text()
    catalog = (ROOT/'scripts/catalog.gd').read_text()
    state = (ROOT/'scripts/game_state.gd').read_text()
    ai = (ROOT/'scripts/enemy_ai.gd').read_text()
    visual = (ROOT/'scripts/world.gd').read_text()
    nav = (ROOT/'scripts/navigation.gd').read_text()
    map_code = (ROOT/'scripts/world_map.gd').read_text()
    hud = (ROOT/'scripts/hud.gd').read_text()
    targets = parse_expression(layout.split('static func targets()',1)[1].split('\n\treturn ',1)[1])
    items, recipes = literal(catalog,'ITEMS'), literal(catalog,'RECIPES')
    limit, north = literal(layout,'LIMIT'), literal(layout,'NORTH_LIMIT')
    clearance, radius = literal(layout,'NAV_CLEARANCE'), literal(layout,'TARGET_SOLID_RADIUS')
    rects = [literal(layout,'POND')] + literal(layout,'OBSTACLES')
    safe = literal(layout,'SAFE_AREAS')
    for b in literal(layout,'BUILDINGS'):
        x,z=b['center'];w,h=b['size'];rects.append([x-w/2,z-h/2,w,h])
    solid_kinds=literal(layout,'SOLID_TARGET_KINDS')
    centers=[(t['pos'][0],t['pos'][2]) for t in targets if t['kind'] in solid_kinds]
    def in_rect(p, r, pad=0.0):
        x,z=p;rx,rz,w,h=r
        return rx-pad <= x < rx+w+pad and rz-pad <= z < rz+h+pad
    def static_free(p):
        x,z=p
        return -limit<=x<=limit and north<=z<=limit and not any(in_rect(p,r,clearance) for r in rects) and all(math.dist(p,c)>radius for c in centers)
    grid={(x,z) for x in range(-limit,limit+1) for z in range(north,limit+1) if static_free((x,z))}
    def clear(p):
        return static_free(p) and (round(p[0]),round(p[1])) in grid
    def segment(a,b):
        n=max(1,math.ceil(math.dist(a,b)/.2))
        return all(clear((a[0]+(b[0]-a[0])*i/n,a[1]+(b[1]-a[1])*i/n)) for i in range(n+1))
    def bfs(start):
        parent={start:None}; depth={start:0}; queue=collections.deque([start])
        while queue:
            x,z=queue.popleft()
            for dx,dz in ((1,0),(-1,0),(0,1),(0,-1),(1,1),(1,-1),(-1,1),(-1,-1)):
                to=(x+dx,z+dz)
                if to not in grid or to in parent:continue
                if dx and dz and ((x+dx,z) not in grid or (x,z+dz) not in grid):continue
                parent[to]=(x,z);depth[to]=depth[(x,z)]+1;queue.append(to)
        return parent,depth
    def route(parent, end):
        path=[]
        while end is not None:
            path.append(end);end=parent[end]
        return path[::-1]
    spawn=literal(layout,'SPAWN'); origin=(spawn[0],spawn[2]); parent,depth=bfs(origin)
    check(north==-67 and limit==29, 'New northern boundary preserves original east/west/south bounds')
    check(len(parent)==len(grid),'Full expanded reference grid is connected to village spawn')
    check(segment((0,-29),(0,-34)), 'Old gate centre is an unobstructed north passage')
    check(not segment((8,-43),(12,-43)), 'Ironroot cover blocks a direct melee/movement segment')
    for target in targets:
        id=target['id'];at=(target['pos'][0],target['pos'][2]);enemy=target['kind']=='enemy'
        if enemy:
            check(clear(at),f'Enemy home is on clear terrain: {id}')
            check(not any(in_rect(at,r) for r in safe), f'Enemy home is outside safe areas: {id}')
            check(target.get('speed',2.45) < 4.4,f'Walking player can outrun pursuit: {id}')
            check(target.get('drop','slime_gel') in items and target.get('xp',26)>0 and target.get('coins',6)>0,f'Valid species drop and rewards: {id}')
        if at[1]>=-31:continue
        candidates=[p for p in parent if math.dist(p,at)<=2.15 and (not enemy or (not any(in_rect(p,r) for r in safe) and segment(p,at)))]
        check(bool(candidates),f'Valid dry approach to new target: {id}')
        if candidates:
            finish=min(candidates,key=lambda p:depth[p]+math.dist(p,at)*.05)
            path=route(parent,finish)
            check(all(segment(a,b) for a,b in zip(path,path[1:])),f'Continuous route samples clear for new target: {id}')
    cover_parent,_=bfs((8,-43));cover_route=route(cover_parent,(12,-43))
    check(len(cover_route)>6 and all(segment(a,b) for a,b in zip(cover_route,cover_route[1:])), 'Reference route detours around Ironroot cover without clipping')
    check(all(t['kind'] in ['ranger','bank','campfire','forge','market'] for t in targets if t['id'] in ['ranger','camp_bank','camp_fire','camp_forge','camp_shop']), 'Camp uses existing services plus the expedition giver')
    check(literal(catalog,'FRONTIER_GOALS')=={'wolves':3,'coal':3,'warden':1}, 'Expedition goals have explicit bounded counts')
    check(recipes['smelt_steel']['cost']=={'iron_bar':1,'coal':2} and recipes['forge_steel']['cost']=={'steel_bar':3}, 'Steel ingredient chain is fully defined')
    check(all(recipes[k]['requires_frontier'] and recipes[k]['level']==5 for k in ['smelt_steel','forge_steel']), 'Both steel recipes require quest unlock and Smithing 5')
    check(items['steel_sword']['damage']==12 and items['iron_sword']['damage']==9,'Steel offers an explicit equipment upgrade')
    check('target_position(id)' in body(state,'_in_interaction_range') and 'segment_clear' in body(state,'_in_interaction_range'), 'Player reach uses live enemy position and line of sight')
    check('str(world[id]["state"]) != "return"' in body(state,'enemy_attackable'), 'Returning state rejects attack eligibility')
    check('not Layout.is_safe' not in body(state,'enemy_attackable') and 'not Layout.is_safe' in body(state,'_in_interaction_range'), 'Safe-area protection blocks impact, not remote approach requests')
    check('Layout.is_safe(world)' in body(nav,'route') and 'segment_clear(world, to)' in body(nav,'route'), 'Combat approach cells exclude safety and obstructed melee')
    check('_pursuit_time > 12.0' in body(state,'_update_pursuit') and '_pursuit_repath = 0.30' in body(state,'_update_pursuit'), 'Single-click player pursuit is time-limited and repath-throttled')
    check('Combat.contains_point(origin, status["strike_facing"]' in body(ai,'step') and '_combat_line_clear(origin, player, navigation)' in body(ai,'step') and 'navigation.segment_clear(from, to)' in body(ai,'_combat_line_clear') and 'Layout.segment_crosses_safe' in body(ai,'_combat_line_clear'), 'Enemy impact rechecks distance, cover and safe-town crossings')
    check('player.distance_to(home) > leash' in body(ai,'step') and 'Layout.is_safe(player)' in body(ai,'step'), 'Enemy leash and safe zones are enforced')
    check('status["hp"] = int(definition["hp"])' in body(ai,'_return_home'),'Normal return-home arrival restores health')
    check('status["attack_time"] =' not in body(ai,'provoke') and 'status["state_time"] =' not in body(ai,'provoke'), 'Reprovoking cannot reset attack or windup timers')
    check('_spacing_ok' in body(ai,'_move') and 'navigation.enemy_segment_clear(here, candidate)' in body(ai,'_move'), 'Enemy movement checks crowd spacing and static obstacles')
    check('active_target =' not in ai and '_hit_enemy' not in ai and '_finish_harvest' not in ai,'Enemy AI cannot manufacture player actions or rewards')
    hit=body(state,'_hit_enemy')
    check(hit.index('status["alive"] = false')<hit.index('character["coins"] ='),'Enemy death commits before any rewards')
    check('if not _consume_action(id)' in hit and 'if not enemy_attackable(id)' in hit,'Each kill handler consumes a valid single action and revalidates target')
    check('_frontier_progress("coal")' in body(state,'_finish_harvest') and '_frontier_progress("wolves")' in hit and '_frontier_progress("warden")' in hit, 'Actual gathering and kills feed the expedition milestones')
    check('if species == "mossling"' in hit and '_quest_progress("slimes")' in hit,'Frontier kills cannot satisfy the starter mossling task')
    check('data.get("frontier", {})' in body(state,'_restore_character') and '"frontier": {"started": false' in body(state,'_new_character'), 'Legacy characters receive an empty additive expedition field')
    check('root.position = Terrain.grounded(Game.target_position(id))' in visual and 'pick.rotation.y = visual.rotation.y' in visual,'Moving enemy root and click-box orientation follow simulation presentation')
    check('pick.collision_layer = 2 if bool(status["alive"]) else 0' in visual,'Dead enemies stop intercepting clicks')
    check('Game.target_position(id)' in map_code and 'Layout.MAP_BOUNDS' in map_code, 'Map uses expanded bounds and live enemy markers')
    check('Game.frontier_ready()' in hud and 'frontier_quest' in hud and 'quest_locked' in hud,'HUD exposes expedition progress and steel unlock state')
    check('config/custom_user_dir_name="FFDRealms_Prototype"' in (ROOT/'project.godot').read_text(), 'No new save directory is introduced')
    check('frontier_runner.gd' in (ROOT/'Run Tests.bat').read_text(),'Windows runner includes the new native regression suite')
    report={'scope':'Source/data and independent reference navigation checks only; no GDScript execution', 'passed':sum(r['passed'] for r in results), 'failed':sum(not r['passed'] for r in results), 'checks':results}
    (ROOT/'docs/frontier_check_results.json').write_text(json.dumps(report,indent=2))
    print(f"FRONTIER REFERENCE RESULT: {report['passed']} passed; {report['failed']} failed")
    return int(report['failed']>0)

if __name__=='__main__':
    raise SystemExit(main())
