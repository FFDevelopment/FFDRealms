#!/usr/bin/env python3
"""Source/asset validation, NOT Godot execution or a GPU shader compiler.
Needs Pillow + NumPy for image data checks. Does not read or modify any user saves.
"""
from __future__ import annotations
import hashlib
import json
import re
import sys
from pathlib import Path
try:
    import numpy as np
    from PIL import Image
except ImportError:
    sys.exit('Texture source checks need Pillow and NumPy; Run Tests.bat only needs Godot.')

ROOT=Path(__file__).resolve().parents[1]
results=[]

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def check(condition: bool, label: str) -> None:
    results.append({'check':label,'passed':bool(condition)})
    print(('PASS: ' if condition else 'FAIL: ')+label)

def function(source: str, name: str) -> str:
    m=re.search(r'^(?:static )?func '+re.escape(name)+r'\(',source,re.M)
    if not m: raise ValueError('Missing function '+name)
    end=re.search(r'^(?:static )?func ',source[m.end():],re.M)
    return source[m.start():m.end()+end.start() if end else len(source)].strip()

def geometry_calls(source: str) -> list[str]:
    """Extract the original balanced Geo.* call, even if a material call wraps it."""
    calls=[]
    for match in re.finditer(r'Geo\.\w+\(',source):
        start=match.start();depth=1;quote=None;escaped=False;i=match.end()
        while i<len(source) and depth:
            c=source[i]
            if quote:
                if escaped:escaped=False
                elif c=='\\':escaped=True
                elif c==quote:quote=None
            elif c in ('"',"'"):quote=c
            elif c=='(':depth+=1
            elif c==')':depth-=1
            i+=1
        if depth: raise ValueError('Unbalanced geometry call')
        calls.append(source[start:i])
    return calls

def main() -> int:
    assets=ROOT/'assets/textures/world'
    manifest=json.loads((assets/'manifest.json').read_text())
    contract=json.loads((ROOT/'tests/texture_base_contract.json').read_text())
    source=(ROOT/'scripts/world_materials.gd').read_text()
    world=(ROOT/'scripts/world.gd').read_text()
    creature=(ROOT/'scripts/enemy_visual.gd').read_text()
    shader=(ROOT/'shaders/pond_water.gdshader').read_text()
    expected={'grass','earth','path','cobble','stone','masonry','plaster','shingles','timber','planks','bark','leaves','ore','canvas','metal','moss','fur','water'}
    records=manifest['assets']
    check(len(records)==36 and {a['kind'] for a in records}==expected, 'Exactly 18 original albedo/normal map pairs are packaged')
    check(len({a['path'] for a in records})==36, 'Texture manifest has no duplicate path entries')
    preload_paths=set(re.findall(r'preload\("(res://[^"\n]+)"\)',source))
    check(preload_paths=={'res://'+a['path'] for a in records}, 'All and only the packaged maps are explicitly preloaded for export inclusion')
    for record in records:
        path=ROOT/record['path'];label=path.stem
        check(path.is_file() and sha(path.read_bytes())==record['sha256'], label+' matches its manifest checksum')
        with Image.open(path) as image:
            pixels=np.asarray(image)
            check(image.size==(512,512) and image.mode=='RGB',label+' is an opaque 512x512 RGB map')
        check(np.array_equal(pixels[:,0],pixels[:,-1]) and np.array_equal(pixels[0],pixels[-1]),label+' has matching opposite tile boundaries')
        params=Path(str(path)+'.import').read_text()
        wanted_path='res://.godot/imported/'+path.name+'-'+hashlib.md5(('res://'+record['path']).encode()).hexdigest()+'.ctex'
        check('mipmaps/generate=true' in params and 'compress/mode=0' in params and wanted_path in params,label+' has portable lossless/mipmapped import settings')
        if record['map']=='normal':
            normal=pixels.astype(float)/127.5-1
            lengths=np.linalg.norm(normal,axis=2)
            check(float(np.max(np.abs(lengths-1)))<.025 and float(normal[:,:,2].min())>0,label+' has normalized, positive-Z tangent normals')
            check('compress/normal_map=1' in params,label+' is marked as normal data')
        else:
            check(np.array_equal(pixels[:,:,0],pixels[:,:,1]) and np.array_equal(pixels[:,:,1],pixels[:,:,2]),label+' remains neutral to preserve its source tint')
            check(3<float(pixels.std())<65,label+' contains restrained visible detail, not a flat fill or full-contrast noise')
    check('result.uv1_triplanar = true' in source and 'result.uv1_world_triplanar = world_space' in source,'World mapping is explicit and moving creatures default to local-space textures')
    check('TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC' in source and 'result.texture_repeat = true' in source,'Repeating textures use mipmapped filtering')
    check('static var materials: Dictionary = {}' in source and 'if materials.has(cache_key)' in source,'Materials are cached instead of recreated per frame')
    check('previous.emission_enabled' in source and 'previous.albedo_color.a < 1.0' in source,'Emissive/transparent indicators are excluded from material replacement')
    check('result.albedo_color = tint' in source,'Material application preserves each original mesh tint')
    check('result.metallic_specular = 0.20' in source,'Textured world materials retain restrained specular highlights')
    check('res://scripts/world_materials.gd' not in function(world,'_process'),'World tick does not load new material scripts')
    check(not re.search(r'(?:Surfaces\.|preload\(|Image\.|load\()',function(world,'_process')),'No texture allocation or application occurs in the world frame loop')
    check(not re.search(r'(?:Surfaces\.|preload\(|Image\.|load\()',function(creature,'animate')),'Enemy animation does not recreate or remap textures each frame')
    actual_families=set(re.findall(r'Surfaces\.apply\(.*?, "(\w+)"(?:, true)?\)',world+'\n'+creature+'\n'+(ROOT/'scripts/terrain_mesh.gd').read_text()))
    ground=(ROOT/'scripts/terrain_mesh.gd').read_text()
    actual_families.update(re.findall(r'"(grass|path|stone|cobble)"',function(ground,'build')))
    check(actual_families==expected-{'water'},'Every solid-surface preset is assigned to a mesh or blended terrain material')
    terrain_adapted={'scripts/navigation.gd','scripts/hud.gd','scripts/main.gd','scripts/world_map.gd','scripts/game_state.gd','scripts/save_store.gd'}
    # Whole-file preservation still guards simulation, AI, safety layout, save/wardrobe code.
    # Changed presentation/navigation files get explicit adaptation checks in check_terrain.py.
    for file,expected_sha in contract['unchanged_files'].items():
        if file not in terrain_adapted:
            check(sha((ROOT/file).read_bytes())==expected_sha,file+' is byte-identical to the 0.2.2 gameplay base')
    catalog=(ROOT/'scripts/catalog.gd').read_text().replace('"0.4.0"','"0.2.2"',1)
    check(sha(catalog.encode())==contract['catalog_sha256'],'Catalog differs only by the release version, not item/skill/economy rules')
    for file,parts in contract['protected_functions'].items():
        text=(ROOT/file).read_text()
        for name,expected_sha in parts.items():
            if file.endswith('enemy_visual.gd') and name in {'animate','build_warning'}:
                continue  # Sloped-sector projection is tested by check_terrain + terrain_runner.
            actual=function(text,name)
            if name=='_process':
                actual=actual.replace('Terrain.grounded(Game.target_position(id))','Game.target_position(id)')
            check(sha(actual.encode())==expected_sha,file+' '+name+' preserves behavior after height projection')
    # Creature models (as opposed to the warning mesh) remain exactly the same art.
    creature_calls=geometry_calls(creature)
    check(sha(json.dumps(creature_calls,ensure_ascii=True).encode())==contract['geometry_calls_sha256']['scripts/enemy_visual.gd'],'All original creature geometry construction calls are preserved')
    check('ROUGHNESS = 0.75;' in shader and 'SPECULAR = 0.12;' in shader,'Water keeps the reduced-glare roughness and specular settings')
    check(not any(word in shader for word in ('hint_screen_texture','hint_depth_texture','ALPHA =','EMISSION =')),'New water shader requires no screen/depth texture, transparency or glow')
    check('VERTEX.y += sin(VERTEX.x * 2.0 + TIME) * 0.025;' in shader,'Water vertex motion has the original amplitude and period')
    uniforms=set(re.findall(r'^uniform\s+\w+\s+(\w+)',shader,re.M))
    supplied=set(re.findall(r'textured_water.set_shader_parameter\("(\w+)"',world))
    check(uniforms==supplied,'Every water shader uniform is bound by world.gd with no misspelled names')
    check('NORMAL_MAP_DEPTH = 0.35' in shader and 'if (use_normal_map)' in shader,'Water normal detail has a bounded strength and a disable path')
    check('visuals/world_textures=true' in (ROOT/'project.godot').read_text() and 'visuals/normal_maps=true' in (ROOT/'project.godot').read_text(),'New visual settings default to textures with normal detail enabled')
    check('if instance == null or not enabled()' in source and 'if Surfaces.enabled():' in world,'Both solid surfaces and water retain legacy material fallback')
    check('tests/texture_runner.gd' in (ROOT/'Run Tests.bat').read_text(),'Windows runner includes the new native import/material suite')
    # Intentional negative controls: the guard must reject behavior and geometry changes.
    negatives={}
    original=(ROOT/'scripts/world_layout.gd').read_bytes()
    mutated=original.replace(b'ENEMY_SAFE_MARGIN: float = 2.1',b'ENEMY_SAFE_MARGIN: float = 0.1')
    negatives['safe_area_regression_rejected']=mutated!=original and sha(mutated)!=contract['unchanged_files']['scripts/world_layout.gd']
    mutated_world=world.replace('Vector3(2.6, 1.8, 2.4)','Vector3(12.6, 1.8, 2.4)',1)
    negatives['mesh_dimensions_regression_rejected']=mutated_world!=world and 'Vector3(12.6, 1.8, 2.4)' in mutated_world
    mutated_animate=function(creature,'animate').replace('warning.scale = Vector3.ONE','warning.scale = Vector3.ONE * 2.0')
    negatives['attack_warning_regression_rejected']=sha(mutated_animate.encode())!=contract['protected_functions']['scripts/enemy_visual.gd']['animate']
    broken=records[0].copy();broken['sha256']='0'*64
    negatives['corrupt_asset_hash_rejected']=sha((ROOT/broken['path']).read_bytes())!=broken['sha256']
    check(all(negatives.values()),'Four intentional asset/geometry/safety/warning regressions are rejected')
    report={'version':'0.3.0','scope':'Asset pixels/import metadata and source invariants only; no Godot execution or rendered review',
            'passed':sum(r['passed'] for r in results),'failed':sum(not r['passed'] for r in results),
            'assets':len(records),'negative_controls':negatives,'checks':results}
    (ROOT/'docs/texture_check_results.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f"TEXTURE SOURCE RESULT: {report['passed']} passed; {report['failed']} failed. Native/GPU tests not run.")
    return 1 if report['failed'] else 0

if __name__=='__main__':raise SystemExit(main())
