#!/usr/bin/env python3
"""Bake the authored heightfield, material masks, and matching relief map.
Reproducible offline art tooling: Python 3 + numpy + Pillow. Not required to play.
No player saves, network calls, or external/generated art services are used.
"""
from __future__ import annotations
import hashlib
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests'))
from check_project import literal, parse_expression

ORIGIN = (-33.0, -71.0)
STEP = 0.5
NX, NZ = 133, 209
WATER = -0.25
MAX_GRADE = 0.70
MAP_PPM = 8
# These replace the old flat path boxes, using their exact horizontal footprints.
ROADS = [(0,-11,3.6,31),(-8,-5,17,3.2),(8,-10,17,3.2),(7,8,15,3),
         (0,20,3.6,14),(0,-42,3.6,36),(-7,-35,14,2.8),(8,-40,16,2.8)]

def smooth(a, b, x):
    t = np.clip((x-a)/(b-a), 0., 1.)
    return t*t*(3.-2.*t)

def rect_distance(x,z,rect):
    rx,rz,w,d=rect
    return np.hypot(np.maximum(np.maximum(rx-x,x-rx-w),0.),
                    np.maximum(np.maximum(rz-z,z-rz-d),0.))

def rect_mask(x,z,rect,feather=1.):
    return 1.-smooth(0.,feather,rect_distance(x,z,rect))

def blend(a,b,w):
    return a*(1.-w)+b*w

def authored_height(x,z,buildings,obstacles,targets):
    # Gentle lowland undulations and larger authored hills; no random world reseeding.
    h=.16+.25*np.sin(x*.22+z*.08)*np.sin(z*.17)+.14*np.sin(x*.36-z*.12)
    h += 4.7*smooth(18.,67.,-z)
    for cx,cz,rx,rz,amplitude in [(-21,-19,10,12,2.6),(22,-17,12,12,1.6),
                                 (21,-55,12,20,2.6),(-22,-54,12,17,1.2),(-25,21,10,11,1.7)]:
        h += amplitude*np.exp(-((x-cx)/rx)**2-((z-cz)/rz)**2)
    # Broad, smooth road grade. Its slopes share the same surface as the world.
    road=rect_mask(x,z,(-1.8,-62,3.6,43),3.5)
    h=blend(h,4.8*smooth(18.,63.,-z),road)
    for rect,level,feather in [((-15,-8,27,29),0.,5.),((9,-23,19,15),1.05,5.),
                                ((-27,-41,20,10),2.3,6.),((-10,-67,21,14),4.8,5.)]:
        h=blend(h,level,rect_mask(x,z,rect,feather))
    # Pond bank stays dry and reachable on every side, including its corners.
    pond=(13.,4.,12.,11.)
    shore_distance=rect_distance(x,z,pond)
    h=blend(h,.02,1.-smooth(1.6,4.0,shore_distance))
    inside=(x>=13)&(x<=25)&(z>=4)&(z<=15)
    edge=np.minimum.reduce([x-13,25-x,z-4,15-z])
    basin=WATER-.12-1.2*smooth(0.,3.,edge)
    h=np.where(inside,basin,h)
    return h

def sample_height(heights,x,z):
    """Barycentric interpolation with the EXACT diagonal used by the Godot mesh."""
    gx=np.clip((np.asarray(x)-ORIGIN[0])/STEP,0.,NX-1.000001)
    gz=np.clip((np.asarray(z)-ORIGIN[1])/STEP,0.,NZ-1.000001)
    ix=np.floor(gx).astype(int);iz=np.floor(gz).astype(int)
    u=gx-ix;v=gz-iz
    a=heights[iz,ix];b=heights[iz,ix+1];c=heights[iz+1,ix+1];d=heights[iz+1,ix]
    return np.where(v<=u,a+(b-a)*u+(c-b)*v,a+(c-d)*u+(d-a)*v)

def land_masks(x,z):
    road=np.zeros_like(x)
    for cx,cz,w,d in ROADS:
        road=np.maximum(road,rect_mask(x,z,(cx-w/2,cz-d/2,w,d),.48))
    road=np.maximum(road,rect_mask(x,z,(-27,-41,20,10),.85))
    quarry=np.maximum(rect_mask(x,z,(8.5,-22,19,14),1.4),rect_mask(x,z,(11.5,-66,17,26),1.8))
    square=1.-smooth(7.7,8.45,np.hypot(x,z-5))
    ruins=rect_mask(x,z,(-8.5,-65,17,10),.65)
    cobble=np.maximum(square,ruins)
    stone=quarry*(1.-road)*(1.-cobble)
    road=road*(1.-cobble)
    return road,stone,cobble

def land_color(x,z,h):
    base=np.zeros((*x.shape,3),dtype=np.float64)+np.array([.39,.49,.31])
    woods=(1.-smooth(-13.,-7.,x))*smooth(7.,17.,-z)
    base=blend(base,np.array([.28,.40,.25]),woods[...,None]*.85)
    high=smooth(2.8,7.,h)
    base=blend(base,np.array([.49,.53,.37]),high[...,None]*.7)
    variation=(np.sin(x*.45+z*.17)*np.sin(z*.39)+np.sin(x*.17-z*.52)*.5)*.022
    base=np.clip(base+variation[...,None],0,1)
    road,stone,cobble=land_masks(x,z)
    grass=np.maximum(0.,1.-road-stone-cobble)
    color=base*grass[...,None]+np.array([.65,.56,.40])*road[...,None]
    color+=np.array([.51,.52,.45])*stone[...,None]+np.array([.63,.60,.48])*cobble[...,None]
    shore=(1.-smooth(.2,1.4,rect_distance(x,z,(13,4,12,11))))*(1.-road)*(1.-cobble)
    color=blend(color,np.array([.50,.49,.34]),shore[...,None]*.55)
    return np.clip(color,0,1),np.stack([road,stone,cobble],axis=-1)

def pixels_world(bounds,ppm):
    bx,bz,w,d=bounds
    width,height=int(w*ppm),int(d*ppm)
    return np.meshgrid(bx+(np.arange(width)+.5)/ppm,bz+(np.arange(height)+.5)/ppm)

def save_rgb(path,pixels):
    Image.fromarray(np.uint8(np.clip(np.round(pixels*255.),0,255))).save(path,optimize=True)

def write_import(path,repeat=False,normal=False):
    rel=path.relative_to(ROOT).as_posix();resource='res://'+rel
    dest='res://.godot/imported/'+path.name+'-'+hashlib.md5(resource.encode()).hexdigest()+'.ctex'
    Path(str(path)+'.import').write_text(f'''[remap]
importer="texture"
type="CompressedTexture2D"
path="{dest}"
metadata={{"vram_texture": false}}

[deps]
source_file="{resource}"
dest_files=["{dest}"]

[params]
compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map={1 if normal else 0}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
''')

def main():
    layout=(ROOT/'scripts/world_layout.gd').read_text()
    buildings=literal(layout,'BUILDINGS'); obstacles=literal(layout,'OBSTACLES')
    targets=parse_expression(layout.split('static func targets()',1)[1].split('\n\treturn ',1)[1])
    x,z=np.meshgrid(ORIGIN[0]+np.arange(NX)*STEP,ORIGIN[1]+np.arange(NZ)*STEP)
    heights=authored_height(x,z,buildings,obstacles,targets)
    # Level stone-wall support strips without altering any navigation footprint.
    for rect in obstacles:
        rx,rz,w,d=rect
        level=float(sample_height(heights,rx+w/2,rz+d/2))
        heights=blend(heights,level,rect_mask(x,z,(rx-.2,rz-.2,w+.4,d+.4),1.8))
    # All resource trunks, rocks and service props have stable small support pads.
    for target in targets:
        if target['kind'] in ('enemy','fish'):continue
        tx,_,tz=target['pos']; level=float(sample_height(heights,tx,tz))
        radius=np.hypot(x-tx,z-tz)
        pad=1.-smooth(1.25,2.5,radius)
        heights=blend(heights,level,pad)
    # A 0.75 m engineering smoothing pass removes abrupt stamp shoulders.
    # Implemented with NumPy only; all routes must stay below MAX_GRADE.
    offsets=np.arange(-6,7,dtype=float)
    kernel=np.exp(-0.5*(offsets/1.5)**2);kernel/=kernel.sum()
    for axis in (0,1):
        pads=[(0,0),(0,0)];pads[axis]=(6,6)
        padded=np.pad(heights,pads,mode='edge')
        heights=np.apply_along_axis(lambda row:np.convolve(row,kernel,mode='valid'),axis,padded)
    heights=np.round(heights,6)
    data=ROOT/'data/terrain';assets=ROOT/'assets/textures/terrain'
    data.mkdir(parents=True,exist_ok=True);assets.mkdir(parents=True,exist_ok=True)
    samples=', '.join(f'{value:.6f}' for value in heights.ravel())
    (data/'hearthmere_heightfield.tres').write_text(f'''[gd_resource type="Resource" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/terrain_data.gd" id="1"]

[resource]
script = ExtResource("1")
origin = Vector2({ORIGIN[0]}, {ORIGIN[1]})
step = {STEP}
columns = {NX}
rows = {NZ}
samples = PackedFloat32Array({samples})
''')
    # Control maps are world-aligned; blend strips no longer float over slopes.
    ax,az=pixels_world((*ORIGIN,(NX-1)*STEP,(NZ-1)*STEP),4)
    ah=sample_height(heights,ax,az)
    colors,masks=land_color(ax,az,ah)
    save_rgb(assets/'land_tint.png',colors);save_rgb(assets/'land_blend.png',masks)
    # Map is baked from the SAME height samples, tint and tiling material families.
    bounds=literal(layout,'MAP_BOUNDS');mx,mz=pixels_world(bounds,MAP_PPM)
    mh=sample_height(heights,mx,mz);color,masks=land_color(mx,mz,mh)
    weights=[np.maximum(0.,1.-masks.sum(axis=-1)),masks[...,0],masks[...,1],masks[...,2]]
    tile_mix=np.zeros_like(color)
    for family,freq,weight in zip(['grass','path','stone','cobble'],[.28,.38,.56,.22],weights):
        tex=np.asarray(Image.open(ROOT/f'assets/textures/world/{family}_albedo.png')).astype(float)/255.
        ix=((mx*freq%1.)*tex.shape[1]).astype(int);iz=((mz*freq%1.)*tex.shape[0]).astype(int)
        tile_mix+=tex[iz,ix,:3]*weight[...,None]
    color*=tile_mix
    # Relief direction matches the broad northwest daylight; contours are 1 metre.
    dx=(sample_height(heights,mx+.25,mz)-sample_height(heights,mx-.25,mz))/.5
    dz=(sample_height(heights,mx,mz+.25)-sample_height(heights,mx,mz-.25))/.5
    length=np.sqrt(1.+dx*dx+dz*dz)
    light=(.42*dx+.82+.38*dz)/length
    shade=np.clip(.67+.37*light,.50,1.03)
    contour=np.abs(mh-np.round(mh))<.018+np.hypot(dx,dz)*.015
    contour &= np.hypot(dx,dz)>.07
    color*=shade[...,None]
    color*=np.where(contour,.86,1.)[...,None]
    pond=(mx>=13)&(mx<=25)&(mz>=4)&(mz<=15)&(mh<WATER)
    depth=np.clip((WATER-mh)/1.3,0,1)
    water_color=blend(np.zeros_like(color)+[.34,.52,.50],np.array([.18,.34,.38]),depth[...,None])
    color=np.where(pond[...,None],water_color,color)
    save_rgb(assets/'world_relief.png',color)
    for path in assets.glob('*.png'):write_import(path)
    manifest={'version':'0.3.0','seed':'authored deterministic height functions; no RNG',
              'source_layout_sha256':hashlib.sha256(layout.encode()).hexdigest(),
              'origin':ORIGIN,'step':STEP,'columns':NX,'rows':NZ,
              'vertex_count':NX*NZ,'triangle_count':(NX-1)*(NZ-1)*2,
              'water_height':WATER,'maximum_walkable_grade':MAX_GRADE,
              'roads':ROADS,'map_bounds':bounds,'map_pixels_per_metre':MAP_PPM,
              'minimum_height':float(heights.min()),'maximum_height':float(heights.max()),
              'assets':{p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
                        for p in [data/'hearthmere_heightfield.tres',*sorted(assets.glob('*.png'))]}}
    (data/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({k:v for k,v in manifest.items() if k!='assets'},indent=2))

if __name__=='__main__':main()
