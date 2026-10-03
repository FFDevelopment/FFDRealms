#!/usr/bin/env python3
"""Offline data/source checks and independent geometry/navigation reference checks.
Does NOT execute GDScript, Godot's AStarGrid2D, the UI, or rendered materials.
Optional Shapely adds a separate geometry oracle. No user saves are accessed.
"""
from __future__ import annotations
import collections
import hashlib
import json
import math
import random
import re
from pathlib import Path
from check_project import literal, parse_expression

ROOT = Path(__file__).resolve().parents[1]
results: list[dict] = []

def check(ok: bool, label: str) -> None:
    results.append({'check':label,'passed':bool(ok)})
    print(('PASS: ' if ok else 'FAIL: ') + label)

def body(source: str, name: str) -> str:
    return source.split('func '+name+'(',1)[1].split('\nstatic func ',1)[0].split('\nfunc ',1)[0]

def main() -> int:
    files={name:(ROOT/'scripts'/f'{name}.gd').read_text() for name in ['appearance','actor','wardrobe','hud','main','game_state','navigation','world_layout','enemy_ai']}
    look,actor,wardrobe,hud,state,nav,layout,ai = [files[x] for x in ['appearance','actor','wardrobe','hud','game_state','navigation','world_layout','enemy_ai']]
    defaults, colors, options, labels = [literal(look,x) for x in ['DEFAULTS','COLOR_LABELS','OPTIONS','STYLE_LABELS']]
    check(len(colors)==9 and set(colors)<=set(defaults), 'Nine named independent dye channels have defaults')
    check(all(re.fullmatch('[0-9a-f]{6}',defaults[k]) for k in colors),'Every default color is an opaque RGB hex code')
    check(all(defaults[k] in v and all(x in labels for x in v) for k,v in options.items()),'All garment/hair choices have labels and valid defaults')
    check(options['pants_style']==['denim','slacks','canvas'],'Jeans, slacks and canvas are separate options')
    check(options['shirt_fabric']==['cotton','linen','knit','denim'],'Top has four independently selectable fabrics')
    check(options['shoe_fabric']==['leather','suede'] and options['shoe_style']==['boots','shoes'],'Footwear separates silhouette from material')
    clean=body(look,'sanitize')
    check('Color.html_is_valid(code)' in clean and 'code.length() == 6' in clean,'Sanitizer rejects malformed and alpha-bearing color codes')
    check('value in OPTIONS[key]' in clean and ' is bool' in clean,'Style and visibility inputs are type/allowlist checked')
    check('DEFAULTS.duplicate(true)' in body(look,'defaults'),'Default appearances are deep copies')
    check('Image.FORMAT_RGBA8' in look and 'image.generate_mipmaps()' in look,'Fabric maps have mipmaps and an explicit image format')
    check('textures[style] = texture' in look,'Generated neutral textures are cached by fabric, not dye')
    check('slot_materials[slot] = StandardMaterial3D.new()' in actor,'Mutable materials belong to each actor, not a shared global material')
    check('surface.albedo_color = Color(str(appearance_data[slot]))' in actor and 'surface.albedo_texture = Appearance.fabric_texture(fabric)' in actor,'Dye and fabric use distinct material inputs')
    check('_detail("denim", denim)' in actor and '_detail("slacks", crease)' in actor,'Jeans and slacks have distinct visible mesh details')
    check('apply_appearance(Game.character.get("appearance", {}))' in files['main'],'Main character presentation consumes saved appearance')
    check('draft = Appearance.sanitize(source)' in body(wardrobe,'build') and 'Game.' not in re.sub(r'##[^\n]*','',wardrobe),'Wardrobe preview has no direct Game mutation path')
    check('preview_viewport.own_world_3d = true' in wardrobe and 'preview_viewport.size = Vector2i(440, 570)' in wardrobe,'Preview has an isolated, explicitly sized SubViewport')
    check('ColorPickerButton.new()' in wardrobe and 'picker.edit_alpha = false' in wardrobe,'Each dye uses an opaque color picker')
    check('apply_requested.emit(Appearance.sanitize(draft))' in wardrobe,'Save submits a sanitized draft')
    check('not Layout.is_safe' in body(hud,'show_wardrobe') and 'KEY_C: show_wardrobe()' in hud,'Wardrobe is discoverable through C and gated to safe towns')
    check('Game.cancel_action(false)' in body(hud,'show_wardrobe'),'Opening wardrobe cancels pending gameplay actions')
    check('Game.dispatch("appearance", {"look": look})' in body(hud,'_save_appearance'),'HUD commits through the simulation intent path')
    commit=body(state,'update_appearance')
    check('not Layout.is_safe' in commit and 'Appearance.sanitize(source)' in commit,'Simulation repeats safe-area and input validation independently of UI')
    check(commit.index('Saves.write_profile') < commit.index('character["appearance"] = look') and 'if error != OK:' in commit,'Failed save returns before runtime appearance is committed')
    assignments=re.findall(r'character\["([^"]+)"\]\s*=',commit)
    check(assignments==['appearance'],'Appearance commit cannot assign money, XP, inventory, health or weapons')
    check('Appearance.sanitize(data.get("appearance", {}))' in body(state,'_restore_character'),'Legacy/malformed appearance data restores with safe defaults')
    check('Appearance.sanitize(character.get("appearance", {}))' in body(state,'serialized_character'),'Saved appearance is validated again at serialization')
    check('config/custom_user_dir_name="FFDRealms_Prototype"' in (ROOT/'project.godot').read_text() and 'const SCHEMA: int = 1' in (ROOT/'scripts/save_store.gd').read_text(),'Profile directory and schema are unchanged')
    check('enemy_grid.set_point_solid' in nav and 'Layout.enemy_forbidden' in body(nav,'build'),'Enemy-only grid marks town footprints plus body clearance solid')
    check('points = navigation.enemy_route(here, destination)' in body(ai,'_plan'),'Enemy route planning never uses the player town grid')
    check('navigation.enemy_segment_clear(here, candidate)' in body(ai,'_move'),'Every enemy movement substep checks the protected footprint')
    check(body(ai,'step').count('navigation.enemy_segment_clear(here, candidate)')==2,'Strafing and backing away also use enemy-only movement guards')
    check('navigation.enemy_clear_position(goal)' in body(ai,'_patrol'),'Patrol destinations must be outside enemy-exclusion areas')
    check('navigation.nearest_enemy_position(home)' in body(ai,'reset'),'Spawn and respawn have a valid wilderness-position fallback')
    step=body(ai,'step')
    check(step.index('if not navigation.enemy_clear_position(here):') < step.index('if str(status["state"]) == "return":'),'Invalid runtime placements are repaired before return/combat handling')
    check('Layout.segment_crosses_safe(from, to)' in body(ai,'_combat_line_clear'),'Enemy attacks cannot cross through town between outside endpoints')
    check('Layout.segment_crosses_safe(position_of_player(), at)' in body(state,'_in_interaction_range'),'Player attacks cannot pass through or originate within safe towns')
    check('damage > 0 and not Layout.is_safe(position_of_player())' in body(state,'_update_enemy_retaliation'),'Damage application has a final independent town check')
    check('status["hp"] = int(definition["hp"])' in body(ai,'_return_home') and '_move(id, status,' in body(ai,'_return_home'),'Existing walk-home and heal-on-arrival behavior remains')
    check('status["attack_time"] =' not in body(ai,'provoke'),'Provoking cannot reset enemy attack timing')
    # Independent reference geometry; actual constants are loaded from the project.
    safe=literal(layout,'SAFE_AREAS'); margin=literal(layout,'ENEMY_SAFE_MARGIN')
    check(safe==[[-29,-12,58,41],[-27,-41,20,10]],'Existing town extents retained rather than adding a new return radius')
    check(margin==2.1,'Enemy path footprint includes conservative current-model body clearance')
    def inside(p,r,pad=0.0):
        x,y,w,h=r
        return x-pad <= p[0] <= x+w+pad and y-pad <= p[1] <= y+h+pad
    def crosses(a,b,pad=0.0):
        if not all(math.isfinite(v) for v in (*a,*b)):return True
        for r in safe:
            x,y,w,h=r; low=(x-pad,y-pad); high=(x+w+pad,y+h+pad)
            t0,t1,hit=0.,1.,True
            for j in (0,1):
                d=b[j]-a[j]
                if abs(d)<1e-6:
                    if a[j]<low[j] or a[j]>high[j]:hit=False;break
                else:
                    first,last=(low[j]-a[j])/d,(high[j]-a[j])/d
                    t0=max(t0,min(first,last));t1=min(t1,max(first,last))
                    if t0>t1:hit=False;break
            if hit:return True
        return False
    for i,r in enumerate(safe):
        x,z,w,h=r
        points=[(x,z),(x+w,z),(x+w,z+h),(x,z+h),(x+w/2,z),(x+w,z+h/2),(x+w/2,z+h),(x,z+h/2)]
        for point in points:
            check(inside(point,r),f'Town {i+1} includes edge/corner {point}')
        check(crosses((x-3,z+h/2),(x+w+3,z+h/2)),f'Town {i+1} detected in outside-to-outside crossing')
        check(crosses((x-3,z-3),(x+w+3,z+h+3)),f'Town {i+1} detected in diagonal crossing')
        check(crosses((x,z),(x,z)),f'Town {i+1} detects stationary point on exact boundary')
    check(not crosses((0,-25),(0,-23)),'Ordinary wilderness melee is not blocked by safe geometry')
    check(crosses((math.inf,0),(1,2)),'Non-finite segment fails closed')
    oracle={'executed':False}
    try:
        from shapely.geometry import box, LineString, Point
        rng=random.Random(20261001); mismatch=0; samples=0
        for pad in (0.,margin):
            boxes=[box(r[0]-pad,r[1]-pad,r[0]+r[2]+pad,r[1]+r[3]+pad) for r in safe]
            for _ in range(5000):
                a=(rng.uniform(-34,34),rng.uniform(-71,34));b=(rng.uniform(-34,34),rng.uniform(-71,34))
                expected=any(v.intersects(LineString([a,b])) for v in boxes)
                mismatch+=int(crosses(a,b,pad)!=expected);samples+=1
        check(mismatch==0, '10,000 seeded reference segments match independent Shapely rectangle intersection')
        oracle={'executed':True,'samples':samples,'mismatches':mismatch}
    except ImportError:
        print('SKIP: Optional Shapely geometry oracle unavailable.')
    limit,north=literal(layout,'LIMIT'),literal(layout,'NORTH_LIMIT')
    clearance,radius=literal(layout,'NAV_CLEARANCE'),literal(layout,'TARGET_SOLID_RADIUS')
    rects=[literal(layout,'POND')]+literal(layout,'OBSTACLES')
    for b in literal(layout,'BUILDINGS'):
        x,z=b['center'];w,h=b['size'];rects.append([x-w/2,z-h/2,w,h])
    targets=parse_expression(layout.split('static func targets()',1)[1].split('\n\treturn ',1)[1])
    kinds=literal(layout,'SOLID_TARGET_KINDS');centres=[(t['pos'][0],t['pos'][2]) for t in targets if t['kind'] in kinds]
    def static_free(p):
        x,z=p
        return -limit<=x<=limit and north<=z<=limit and not any(r[0]-clearance<=x<r[0]+r[2]+clearance and r[1]-clearance<=z<r[1]+r[3]+clearance for r in rects) and all(math.dist(p,c)>radius for c in centres)
    base={(x,z) for x in range(-limit,limit+1) for z in range(north,limit+1) if static_free((x,z))}
    enemies={p for p in base if not any(inside(p,r,margin) for r in safe)}
    def rnd(v):return int(math.copysign(math.floor(abs(v)+.5),v))
    def clear(p):return static_free(p) and (rnd(p[0]),rnd(p[1])) in base
    def enemy_segment(a,b):
        if crosses(a,b,margin) or (rnd(b[0]),rnd(b[1])) not in enemies:return False
        n=max(1,math.ceil(math.dist(a,b)/.2))
        return all(clear((a[0]+(b[0]-a[0])*i/n,a[1]+(b[1]-a[1])*i/n)) for i in range(n+1))
    check((0,8) in base and (0,8) not in enemies,'Town spawn is still open to player routes, closed to enemies')
    check((-14,-33) in base and (-14,-33) not in enemies,'Northreach access remains open to player routes')
    for target in targets:
        if target['kind']=='enemy':
            p=(target['pos'][0],target['pos'][2]);check(p in enemies,'Enemy home remains legal with body margin: '+target['id'])
    origin=(-17,-27);destination=(-16,-47)
    parent={origin:None};queue=collections.deque([origin])
    while queue:
        at=queue.popleft()
        if at==destination:break
        for dx,dz in ((1,0),(-1,0),(0,1),(0,-1),(1,1),(1,-1),(-1,1),(-1,-1)):
            to=(at[0]+dx,at[1]+dz)
            if to not in enemies or to in parent:continue
            if dx and dz and ((at[0]+dx,at[1]) not in enemies or (at[0],at[1]+dz) not in enemies):continue
            if not enemy_segment(at,to):continue
            parent[to]=at;queue.append(to)
    check(destination in parent,'Reference enemy return path exists around camp')
    path=[]
    if destination in parent:
        current=destination
        while current is not None:path.append(current);current=parent[current]
        path.reverse()
    check(bool(path) and all(enemy_segment(a,b) for a,b in zip(path,path[1:])),'Every reference detour segment remains outside towns with body margin')
    check(crosses(origin,destination) and math.dist(origin,destination)<len(path)-1,'Detour avoids the direct route through the protected camp')
    # Negative control: removing the exclusion would admit the known bad crossing.
    check(all(static_free((x,-36)) for x in [-6,-5,-4]) and crosses((-4,-36),(-6,-36),margin),'Boundary regression case would pass terrain-only checks but is caught by exclusion')
    check('appearance_runner.gd' in (ROOT/'Run Tests.bat').read_text(),'Native appearance/safety suite included in Windows runner')
    report={'scope':'Data/source and independent Python geometry/navigation only; no GDScript execution', 'passed':sum(r['passed'] for r in results),'failed':sum(not r['passed'] for r in results),'geometry_oracle':oracle,'reference_path_points':len(path),'source_sha256':{k:hashlib.sha256(v.encode()).hexdigest() for k,v in files.items()},'checks':results}
    (ROOT/'docs/appearance_check_results.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f"APPEARANCE REFERENCE RESULT: {report['passed']} passed; {report['failed']} failed")
    return int(report['failed']>0)

if __name__=='__main__':raise SystemExit(main())
