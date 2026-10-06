#!/usr/bin/env python3
"""Check the design's navigation targets and device bounds, not app logic."""
import json
from pathlib import Path
import struct
import zlib

root=Path(__file__).resolve().parent
scene=json.loads((root/'scene.json').read_text())
screens=scene['screens']; ids={s['id'] for s in screens};errors=[]
if len(ids)!=len(screens):errors.append('Duplicate screen IDs')
for s in screens:
 for n in s['nodes']:
  if n.get('target') and n['target'] not in ids:errors.append(f'{s["id"]}: missing {n["target"]}')
  if n['w']<=0 or n['h']<=0:errors.append(f'{s["id"]}: invalid size {n["name"]}')
  if n['x']<-.5 or n['x']+n['w']>s['width']+.5 or n['y']<-.5 or n['y']+n['h']>s['height']+.5:errors.append(f'{s["id"]}: outside device {n["name"]}')
  if n.get('target') and (n['w']<43.99 or n['h']<43.99):errors.append(f'{s["id"]}: small target {n["name"]}')
 if not (root/'proofs'/f'{s["id"]}.svg').exists():errors.append(f'{s["id"]}: missing SVG')
for p in (root/'exports').glob('*'):
 data=p.read_bytes()
 if p.suffix!='.png' or data[:8]!=b'\x89PNG\r\n\x1a\n':
  errors.append(f'{p.name}: invalid native export');continue
 try:
  pos=8;chunks=[]
  while pos<len(data):
   size=struct.unpack('>I',data[pos:pos+4])[0]
   chunk=data[pos+4:pos+8+size]
   crc=struct.unpack('>I',data[pos+8+size:pos+12+size])[0]
   if zlib.crc32(chunk)!=crc:raise ValueError('PNG checksum mismatch')
   chunks.append(chunk[:4]);pos+=size+12
  if chunks[0]!=b'IHDR' or chunks[-1]!=b'IEND' or b'IDAT' not in chunks:
   raise ValueError('Incomplete PNG')
 except (ValueError,IndexError,struct.error) as e:errors.append(f'{p.name}: {e}')
print(json.dumps({'screens':len(screens),'nodes':sum(len(s['nodes']) for s in screens),'errors':errors},ensure_ascii=False,indent=2))
raise SystemExit(bool(errors))
