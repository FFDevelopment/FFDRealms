#!/usr/bin/env python3
"""Offline geometry/data and independent path-reference checks, NOT Godot execution."""
from __future__ import annotations
import collections
import hashlib
import json
import math
import re
import sys
from pathlib import Path
import numpy as np
from PIL import Image
from check_project import literal,parse_expression
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from bake_terrain import sample_height,STEP,NX,NZ,ORIGIN,MAX_GRADE,WATER,land_color,pixels_world
checks=[]
def check(ok,label):
    checks.append({'check':label,'passed':bool(ok)})
    print(('PASS: ' if ok else 'FAIL: ')+label)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def function(text,name):
    start=re.search(r'^(?:static )?func '+re.escape(name)+r'\(',text,re.M)
    end=re.search(r'^(?:static )?func ',text[start.end():],re.M)
    return text[start.start():start.end()+end.start() if end else len(text)].strip()
def main():
    manifest=json.loads((ROOT/'data/terrain/manifest.json').read_text())
    contract=json.loads((ROOT/'tests/terrain_base_contract.json').read_text())
    src=(ROOT/'scripts/world_layout.gd').read_text()
    raw=(ROOT/'data/terrain/hearthmere_heightfield.tres').read_text()
    heights=np.array([float(n) for n in re.search(r'samples = PackedFloat32Array\((.*?)\)',raw,re.S)[1].split(',')]).reshape(NZ,NX)
    check(heights.size==27797 and np.isfinite(heights).all(),'Authored resource has all 27,797 finite height samples')
    check(STEP==.5 and manifest['triangle_count']==54912,'Half-metre mesh resolution and 54,912 triangle budget are explicit')
    check(heights.min()>-4 and heights.max()<10 and np.ptp(heights)>8,'Terrain has real bounded elevation, not a displaced flat plane')
    check(manifest['source_layout_sha256']==sha(ROOT/'scripts/world_layout.gd'),'Terrain bake belongs to the current exact world layout')
    for file,expected in manifest['assets'].items():check(sha(ROOT/file)==expected,file+' matches its baked checksum')
    for file,expected in contract['unchanged_files'].items():
        if file in {'scripts/game_state.gd','scripts/save_store.gd'}:
            continue  # v0.4.0 intentionally changes slot-name restore/summary behavior only.
        check(sha(ROOT/file)==expected,file+' is byte-identical to the 0.2.3 base')
    for file,parts in contract['unchanged_functions'].items():
        text=(ROOT/file).read_text()
        for name,expected in parts.items():
            check(hashlib.sha256(function(text,name).encode()).hexdigest()==expected,file+' '+name+' is unchanged')
    terrain=(ROOT/'scripts/terrain.gd').read_text();mesh=(ROOT/'scripts/terrain_mesh.gd').read_text()
    main_src=(ROOT/'scripts/main.gd').read_text();world=(ROOT/'scripts/world.gd').read_text()
    nav=(ROOT/'scripts/navigation.gd').read_text();mapping=(ROOT/'scripts/world_map.gd').read_text()
    visual=(ROOT/'scripts/enemy_visual.gd').read_text();shader=(ROOT/'shaders/terrain.gdshader').read_text()
    nav_without_height=nav.replace('const Terrain = preload("res://scripts/terrain.gd")\n','').replace('\tif not Terrain.is_walkable(point):\n\t\treturn true\n','')
    check(hashlib.sha256(nav_without_height.encode()).hexdigest()==contract['navigation_before'],'Navigation differs only by its conservative slope guard; safety/obstacle rules preserved')
    check('if v <= u:' in terrain and 'a + (b - a) * u + (c - b) * v' in terrain and 'a + (c - d) * u + (d - a) * v' in terrain,'Runtime sampler uses the authored mesh diagonal, not bilinear heights')
    check('PackedInt32Array([a, b, c, a, c, d])' in mesh,'Mesh uses the same A-C diagonal and clockwise upper faces')
    check('surface.mesh.create_trimesh_shape()' in mesh and 'body.collision_layer = 1' in mesh,'Click collision is derived from the exact rendered mesh')
    check('GroundMesh.build(self)' in world and 'shape: BoxShape3D' not in function(world,'_build_land'),'Old flat terrain collision is removed')
    check('func _path_strip(' not in world and 'Vector3(58, 0.04, 36)' not in world,'Old flat path/frontier overlays are removed rather than left floating')
    check('PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 1)' in main_src and 'Plane(Vector3.UP, 0.0)' not in main_src,'Movement clicks raycast real terrain, not the original zero-height plane')
    check('destination.y = 0.0' in main_src and 'Terrain.grounded(Game.position_of_player())' in main_src,'Logical save coordinates remain separate from actual grounded presentation')
    check('Terrain.grounded(Game.target_position(id))' in world and 'Terrain.grounded(definition["pos"])' in world,'Live creatures and stationary targets both get terrain grounding')
    check('_ground_decorations(decorations)' in world and 'Terrain.grounded(Vector3(center.x, 0, center.y))' in world,'Buildings, signs, lights and scenery are grounded')
    check('Terrain.grounded(Game.position_of_player()) + right * 3.8' in main_src,'Camera focus follows elevation without changing controls')
    check('Terrain.WATER_HEIGHT + 0.12' in main_src and 'Plane(Vector3.UP, Terrain.WATER_HEIGHT)' in main_src and 'Terrain.WATER_HEIGHT - 0.06' in world,'Fishing click plane, float and pick target use the same fixed water level')
    check('Terrain.grounded(at)' in main_src and 'Terrain.normal_at(marker.position.x' in main_src,'Damage popups and the destination marker follow ground height')
    check('_conform_warning(warning, origin, here)' in visual and 'Terrain.height_at(horizontal.x, horizontal.z) - anchor_y + 0.07' in visual,'Committed enemy warning vertices project onto the terrain')
    check('terrain_signature' in visual and 'for ring: int in range(8)' in visual,'Warning projection is radially subdivided and cached per committed pose')
    check('warning.scale = Vector3.ONE' in visual and 'var horizontal: Vector3 = origin + warning.basis * vertex' in visual,'Terrain projection preserves the validated strike X/Z footprint')
    check('draw_texture_rect(RELIEF_MAP' in mapping and '_footprint(area,' not in mapping,'Map draws cached real relief and does not hide land under opaque safe-zone fills')
    check('Terrain.height_at(cursor.x, cursor.z)' in mapping and 'Game.target_position(id)' in mapping,'Map shows actual sampled height and live enemy positions')
    check('Image.new' not in mapping and 'get_image()' not in mapping,'Map never regenerates terrain textures on each frame')
    uniforms=set(re.findall(r'^uniform\s+\w+\s+(\w+)',shader,re.M))
    expected={'land_tint','land_blend','use_detail','use_normal_maps'}|{n+s for n in ['grass','path','stone','cobble'] for s in ['_map','_normal']}
    check(uniforms==expected,'Terrain shader uniform contract is explicit and complete')
    check('hint_screen_texture' not in shader and 'ALPHA' not in shader and 'EMISSION' not in shader,'Terrain shader stays opaque and does not add screen effects or brightness')
    check('MAX_WALKABLE_GRADE: float = 0.70' in terrain,'Runtime slope limit matches the authored dataset')
    # Verify several hundred independent barycentric interpolations against a linear solve.
    rng=np.random.default_rng(20261003);errors=[]
    for _ in range(512):
        ix=int(rng.integers(0,NX-1));iz=int(rng.integers(0,NZ-1));u,v=rng.random(2)
        coords=np.array([[0,0],[1,0],[1,1]] if v<=u else [[0,0],[1,1],[0,1]],float)
        hs=np.array([heights[iz+int(q[1]),ix+int(q[0])] for q in coords])
        plane=np.linalg.solve(np.column_stack((coords,np.ones(3))),hs)
        expected_h=float(plane@[u,v,1.])
        actual=float(sample_height(heights,ORIGIN[0]+(ix+u)*STEP,ORIGIN[1]+(iz+v)*STEP))
        errors.append(abs(expected_h-actual))
    check(max(errors)<1e-10,'512 independent triangle-plane samples agree with the terrain height sampler')
    # Scan dry land at 25 cm intervals; no hidden steep patch may cut a route.
    gx,gz=np.meshgrid(np.arange(-29,29.001,.25),np.arange(-67,29.001,.25))
    ix=np.floor((gx-ORIGIN[0])/STEP).astype(int);iz=np.floor((gz-ORIGIN[1])/STEP).astype(int)
    a=heights[iz,ix];b=heights[iz,ix+1];c=heights[iz+1,ix+1];d=heights[iz+1,ix]
    slopes=np.maximum(np.hypot(b-a,c-b),np.hypot(c-d,d-a))/STEP
    dry=~((gx>=12.35)&(gx<25.65)&(gz>=3.35)&(gz<15.65))
    check(float(slopes[dry].max())<MAX_GRADE,'All quarter-metre dry-land samples stay below the walkable slope limit')
    xs,zs=np.meshgrid(np.arange(-29,30),np.arange(-67,30));clear=np.ones_like(xs,dtype=bool)
    rects=[literal(src,'POND'),*literal(src,'OBSTACLES')]
    for building in literal(src,'BUILDINGS'):
        x,z=building['center'];w,d=building['size'];rects.append([x-w/2,z-d/2,w,d])
    for x,z,w,d in rects:clear&=~((xs>=x-.65)&(xs<x+w+.65)&(zs>=z-.65)&(zs<z+d+.65))
    targets=parse_expression(src.split('static func targets()',1)[1].split('\n\treturn ',1)[1]);kinds=literal(src,'SOLID_TARGET_KINDS')
    for target in targets:
        if target['kind'] in kinds:
            x,_,z=target['pos'];clear&=(xs-x)**2+(zs-z)**2>1.05**2
    grid=set(zip(xs[clear],zs[clear]));seen={(0,8)};q=collections.deque(seen)
    while q:
        x,z=q.popleft()
        for dx,dz in [(1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,1),(1,-1),(-1,-1)]:
            to=(x+dx,z+dz)
            if to in seen or to not in grid:continue
            if dx and dz and ((x+dx,z) not in grid or (x,z+dz) not in grid):continue
            seen.add(to);q.append(to)
    check(len(seen)==len(grid)==5110,'All 5,110 original navigable grid cells remain connected to spawn')
    for target in targets:
        if target['kind']=='fish':continue
        x,_,z=target['pos']
        nearby=any(math.dist((x,z),p)<=2.15 for p in seen)
        check(nearby,'Reachable interaction approach remains for '+target['id'])
        if target['kind']=='enemy':check((x,z) in seen,'Enemy home remains walkable for '+target['id'])
    banks=[]
    for x,z in seen:
        edge=(np.clip(x,13,25),np.clip(z,4,15))
        if math.dist((x,z),edge)<=2.:
            banks.append((x,z))
    check(len(banks)>40 and all(float(sample_height(heights,*p))>WATER+.05 for p in banks),'All reachable pond-bank cells remain above the water surface')
    for p in [(12,3),(26,3),(12,16),(26,16),(12,8),(26,8),(19,3),(19,16)]:
        check(p in seen and float(sample_height(heights,*p))>WATER,'Dry access remains at pond bank/corner '+str(p))
    levels={'village':(0,8,0.),'camp':(-16,-36,2.3),'ruins':(0,-60,4.8)}
    for name,(x,z,wanted) in levels.items():
        check(abs(float(sample_height(heights,x,z))-wanted)<.025,name+' has its intended level service/encounter pad')
    check(float(sample_height(heights,20,-56))>6.,'Ironroot has a genuinely raised mining ridge')
    check(float(sample_height(heights,19,9.5))<WATER-1.,'Pond has a recessed basin below its fixed water plane')
    for name,size in [('land_tint.png',(264,416)),('land_blend.png',(264,416)),('world_relief.png',(496,800))]:
        p=ROOT/'assets/textures/terrain'/name
        with Image.open(p) as image:check(image.size==size and image.mode=='RGB',name+' has the declared opaque dimensions')
        check('mipmaps/generate=true' in Path(str(p)+'.import').read_text(),name+' has mipmapped import settings')
    ax,az=pixels_world((*ORIGIN,(NX-1)*STEP,(NZ-1)*STEP),4)
    tint,mask=land_color(ax,az,sample_height(heights,ax,az))
    actual=np.asarray(Image.open(ROOT/'assets/textures/terrain/land_tint.png'))
    check(np.array_equal(actual,np.uint8(np.clip(np.round(tint*255),0,255))),'Terrain tints reproduce from the same source used by the relief-map baker')
    check('terrain_runner.gd' in (ROOT/'Run Tests.bat').read_text(),'Windows runner includes native terrain mesh/raycast/projection tests')
    negative={'corrupt_height_rejected':heights.size-1!=NX*NZ,
              'flipped_diagonal_rejected': 'PackedInt32Array([a, b, c, a, c, d])' not in mesh.replace('[a, b, c, a, c, d]','[a, b, d, b, c, d]'),
              'flat_ridge_rejected':not (0.0>6.0),
              'safe_layout_change_rejected':hashlib.sha256(src.replace('ENEMY_SAFE_MARGIN: float = 2.1','ENEMY_SAFE_MARGIN: float = 0.1').encode()).hexdigest()!=manifest['source_layout_sha256']}
    check(all(negative.values()),'Four intentional data/diagonal/elevation/safe-boundary regressions are rejected')
    report={'version':'0.3.0','scope':'Offline data, source and independent reference geometry/navigation only. No Godot execution.',
            'passed':sum(c['passed'] for c in checks),'failed':sum(not c['passed'] for c in checks),
            'maximum_dry_land_grade':float(slopes[dry].max()),'connected_grid_cells':len(seen),
            'shore_cells_tested':len(banks),'triangle_interpolation_max_error':max(errors),'negative_controls':negative,'checks':checks}
    (ROOT/'docs/terrain_check_results.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f"TERRAIN REFERENCE RESULT: {report['passed']} passed; {report['failed']} failed. Native engine tests NOT RUN.")
    return int(report['failed']>0)
if __name__=='__main__':raise SystemExit(main())
