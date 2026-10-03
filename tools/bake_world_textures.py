#!/usr/bin/env python3
"""Bake original, deterministic neutral-dye textures. Not needed to play the game.
Requires Python 3, Pillow and NumPy. No network access, external imagery or model service.
Outputs 512px RGB albedo / OpenGL-style normal PNGs and portable Godot import settings.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets' / 'textures' / 'world'
SIZE = 512
Y, X = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64)
FAMILIES = ('grass', 'earth', 'path', 'cobble', 'stone', 'masonry', 'plaster',
            'shingles', 'timber', 'planks', 'bark', 'leaves', 'ore', 'canvas',
            'metal', 'moss', 'fur', 'water')

def noise(cells: int, seed: int, aspect: int = 1) -> np.ndarray:
    """Periodic smooth value noise, equal seeds produce equal files."""
    rng = np.random.default_rng(seed)
    nx, ny = cells, max(1, cells // aspect)
    grid = rng.random((ny, nx))
    fx, fy = X * nx / SIZE, Y * ny / SIZE
    ix, iy = np.floor(fx).astype(int), np.floor(fy).astype(int)
    tx, ty = fx - ix, fy - iy
    tx, ty = tx*tx*(3-2*tx), ty*ty*(3-2*ty)
    a=grid[iy%ny,ix%nx]*(1-tx)+grid[iy%ny,(ix+1)%nx]*tx
    b=grid[(iy+1)%ny,ix%nx]*(1-tx)+grid[(iy+1)%ny,(ix+1)%nx]*tx
    return a*(1-ty)+b*ty

def fbm(seed: int) -> np.ndarray:
    return sum(noise(c,seed+i)*w for i,(c,w) in enumerate(((4,.42),(8,.27),(16,.17),(32,.09),(64,.05))))

def stamp(canvas: Image.Image, fn, args, **kwargs) -> None:
    """Draw copies across the tile boundary without cropped motifs."""
    for oy in (-SIZE,0,SIZE):
        for ox in (-SIZE,0,SIZE):
            pts=[(p[0]+ox,p[1]+oy) for p in args]
            getattr(ImageDraw.Draw(canvas),fn)(pts,**kwargs)

def edges(array: np.ndarray) -> np.ndarray:
    a=array.copy()
    side=(a[:,0]+a[:,-1])*.5; a[:,0]=side; a[:,-1]=side
    top=(a[0]+a[-1])*.5; a[0]=top; a[-1]=top
    return a

def make_surface(kind: str, seed: int) -> tuple[np.ndarray,np.ndarray]:
    rng=np.random.default_rng(seed)
    n=fbm(seed); fine=noise(128,seed+19); micro=rng.random((SIZE,SIZE))
    height=.5*n+.2*fine+.04*micro
    tone=.79+.23*n+.025*(micro-.5)
    if kind in ('grass','moss','leaves'):
        # Overlapping leaves, blades and moss clumps; deliberately not photorealistic.
        canvas=Image.fromarray(np.uint8(np.clip(n*.7+.1,0,1)*255))
        if kind=='grass':
            for _ in range(2600):
                x,y=rng.uniform(0,SIZE,2); length=rng.uniform(4,18); tilt=rng.uniform(-6,6)
                stamp(canvas,'line',[(x,y),(x+tilt,y-length)],fill=int(rng.integers(100,235)),width=int(rng.integers(1,3)))
        else:
            count=620 if kind=='leaves' else 2100
            for _ in range(count):
                x,y=rng.uniform(0,SIZE,2); rad=rng.uniform(5,16) if kind=='leaves' else rng.uniform(1,5)
                stamp(canvas,'ellipse',[(x-rad,y-rad*.45),(x+rad,y+rad*.45)],fill=int(rng.integers(110,224)))
                if kind=='leaves':
                    stamp(canvas,'line',[(x-rad*.8,y),(x+rad*.8,y)],fill=110,width=1)
        strokes=np.asarray(canvas.filter(ImageFilter.GaussianBlur(.42)),dtype=float)/255
        height=.37*n+.55*strokes+.04*fine
        tone=.67+.23*n+.19*strokes
    elif kind in ('earth','path','stone','ore'):
        canvas=Image.fromarray(np.uint8(np.clip(n*.4+.25,0,1)*255))
        if kind in ('earth','path'):
            for _ in range(360 if kind=='path' else 200):
                x,y=rng.uniform(0,SIZE,2); radius=rng.uniform(1.5,6)
                stamp(canvas,'ellipse',[(x-radius,y-radius*.7),(x+radius,y+radius*.7)],fill=int(rng.integers(115,212)))
        else:
            for _ in range(21):
                x,y=rng.uniform(0,SIZE,2)
                pts=[(x,y)]
                for _ in range(6):
                    x+=rng.uniform(-22,22);y+=rng.uniform(9,23);pts.append((x,y))
                stamp(canvas,'line',pts,fill=45 if kind=='stone' else 219,width=2 if kind=='stone' else 5)
        marks=np.asarray(canvas.filter(ImageFilter.GaussianBlur(.6)),dtype=float)/255
        height=.5*n+.35*marks+.1*fine
        tone=.64+.28*n+.29*marks
    elif kind=='cobble':
        # Hand-set irregular paving, not a second rectangular brick texture.
        d1=np.full((SIZE,SIZE),1e9);d2=d1.copy();owner=np.zeros((SIZE,SIZE),dtype=int)
        points=[]
        for row in range(8):
            for col in range(7):
                points.append(((col+.5+(row%2)*.5+rng.uniform(-.20,.20))*SIZE/7 % SIZE,
                               (row+.5+rng.uniform(-.20,.20))*SIZE/8 % SIZE))
        for index,(cx,cy) in enumerate(points):
            dx=(X-cx+SIZE*.5)%SIZE-SIZE*.5;dy=(Y-cy+SIZE*.5)%SIZE-SIZE*.5
            distance=dx*dx+dy*dy
            first=distance<d1
            d2=np.where(first,d1,np.minimum(d2,distance));owner=np.where(first,index,owner)
            d1=np.minimum(d1,distance)
        margin=np.sqrt(d2)-np.sqrt(d1)
        bevel=np.clip((margin-1.5-(n-.5)*2.0)/6.0,0,1)
        variation=rng.random(len(points))[owner]
        height=.50*bevel+.08*n+.07*variation+.018*fine
        tone=.49+.27*bevel+.18*variation+.1*n
    elif kind in ('masonry','shingles'):
        if kind=='cobble':
            cols,rows=8,10
        elif kind=='masonry':
            cols,rows=5,8
        else:
            cols,rows=8,8
        cell_w,cell_h=SIZE/cols,SIZE/rows
        row=np.floor(Y/cell_h).astype(int)
        xx=(X+(row%2)*cell_w*.5)/cell_w
        col=np.floor(xx).astype(int)
        u=xx-col;v=(Y/cell_h)%1
        # Shared periodic staggered stone/shingle cells, with bevelled seams.
        variation=rng.random((rows,cols))[row%rows,col%cols]
        if kind=='shingles':
            notch=np.power(np.abs(u-.5)*2,6)*3.0
            bottom=(1-v)*cell_h-notch-(n-.5)*2
            seam=np.minimum(np.minimum(u,1-u)*cell_w,bottom)
            bevel=np.clip((seam-1)/4,0,1)
            slate=noise(64,seed+55,8)
            height=bevel*(.38+.23*v)+.08*n+.03*slate
            tone=.45+.31*bevel+.14*variation+.09*slate+.07*n
        else:
            # A tiny warp takes the machined edge off masonry without creating gaps.
            ex=np.minimum(u,1-u)*cell_w;ey=np.minimum(v,1-v)*cell_h
            rounded=np.sqrt(np.maximum(0,4-ex)**2+np.maximum(0,4-ey)**2)
            seam=np.minimum(ex,ey)-rounded*.4
            bevel=np.clip((seam-2-(noise(32,seed+66)-.5)*3)/5,0,1)
            height=bevel*(.50+.08*variation)+n*.1+fine*.025
            tone=.47+.31*bevel+.17*variation+.08*n
    elif kind in ('timber','planks','bark'):
        # Vertical grain and stretched periodic noise keep the wood direction readable.
        grain=noise(64,seed+15,8)
        wave=np.sin(X/SIZE*2*np.pi*25+noise(8,seed+16)*5)
        lines=np.power(np.clip(wave*.5+.5,0,1),9)
        tone=.73+.23*grain-.10*lines+.09*n
        height=.25*n+.38*grain-.08*lines
        if kind=='planks':
            seam=np.minimum(X%128,128-X%128)
            bevel=np.clip((seam-1)/4,0,1)
            tone*=.67+.33*bevel; height*=bevel
        if kind=='bark':
            coarse=np.sin(X/SIZE*2*np.pi*11+noise(4,seed+22)*4)
            fissures=np.power(np.clip(coarse*.5+.5,0,1),12)
            height=.35*grain+.27*n-.22*fissures
            tone=.72+.2*grain+.13*n-.22*fissures
    elif kind=='plaster':
        height=.2*n+.1*fine+.035*micro
        tone=.83+.17*n+.04*(micro-.5)
    elif kind=='canvas':
        warp=np.cos(X*2*np.pi/8);weft=np.cos(Y*2*np.pi/8)
        height=.32+.10*warp+.10*weft+.02*micro
        tone=.85+.05*warp+.05*weft+.05*n
    elif kind=='metal':
        brushed=noise(128,seed+44,32)
        height=.42+.035*brushed+.012*micro
        tone=.84+.10*brushed+.06*n
    elif kind=='fur':
        directional=noise(128,seed+81,8)
        strands=noise(256,seed+82,16)
        height=.40+.12*directional+.05*strands+.08*n
        tone=.74+.17*directional+.055*strands+.12*n
    elif kind=='water':
        wave1=np.sin(2*np.pi*(X*6+Y*3)/SIZE + noise(8,seed+1)*4)
        wave2=np.sin(2*np.pi*(X*3-Y*5)/SIZE + noise(4,seed+2)*3)
        height=.5+.18*wave1+.10*wave2
        tone=.5+.18*wave1+.10*wave2
    tone=edges(np.clip(tone,0,1));height=edges(np.clip(height,0,1))
    return tone,height

def godot_import(path: Path, normal: bool) -> None:
    resource='res://'+path.relative_to(ROOT).as_posix()
    md5=hashlib.md5(resource.encode()).hexdigest()
    imported=f'res://.godot/imported/{path.name}-{md5}.ctex'
    text=f'''[remap]

importer="texture"
type="CompressedTexture2D"
path="{imported}"
metadata={{
"vram_texture": false
}}

[deps]

source_file="{resource}"
dest_files=["{imported}"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map={1 if normal else 2}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=false
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
'''
    Path(str(path)+'.import').write_text(text,encoding='utf-8')

def main() -> None:
    OUT.mkdir(parents=True,exist_ok=True)
    records=[]
    for i,kind in enumerate(FAMILIES):
        tone,height=make_surface(kind,83021+i*97)
        albedo=np.repeat(tone[...,None],3,axis=2)
        # Neutral albedo intentionally multiplies existing, individually chosen tints.
        dx=(np.roll(height,-1,1)-np.roll(height,1,1))*3.0
        dy=(np.roll(height,-1,0)-np.roll(height,1,0))*3.0
        normal=edges(np.stack((-dx,dy,np.ones_like(dx)),axis=-1))
        normal/=np.linalg.norm(normal,axis=-1,keepdims=True)
        normal=normal*.5+.5
        for suffix,data in (('albedo',albedo),('normal',normal)):
            path=OUT/f'{kind}_{suffix}.png'
            Image.fromarray(np.uint8(np.clip(data,0,1)*255+.5)).save(path,optimize=True)
            godot_import(path,suffix=='normal')
            records.append({'path':path.relative_to(ROOT).as_posix(),'kind':kind,'map':suffix,
                'width':SIZE,'height':SIZE,'mode':'RGB','sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
        print('BAKED:',kind)
    manifest={'generator':'tools/bake_world_textures.py','seed_base':83021,'source':'Original deterministic algorithms; no downloaded images',
              'asset_count':len(records),'dimensions':[SIZE,SIZE],'normal_convention':'OpenGL / Y+, RGB, tangent space',
              'color_workflow':'Neutral albedo maps multiplied by existing scene dyes; normal maps are linear data',
              'runtime_dependencies':'Godot only; Python/NumPy/Pillow are build-time tools',
              'assets':records}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Baked',len(records),'maps; PNG bytes:',sum((ROOT/a['path']).stat().st_size for a in records))

if __name__=='__main__':main()
