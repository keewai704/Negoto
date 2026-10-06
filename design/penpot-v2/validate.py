#!/usr/bin/env python3
"""Check the design's navigation targets and device bounds, not app logic."""
import json
from pathlib import Path

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
print(json.dumps({'screens':len(screens),'nodes':sum(len(s['nodes']) for s in screens),'errors':errors},ensure_ascii=False,indent=2))
raise SystemExit(bool(errors))
