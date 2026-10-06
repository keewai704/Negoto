#!/usr/bin/env python3
"""Draws the Negoto app icon (1024x1024, opaque). Requires Pillow."""
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
img = Image.new("RGB", (S, S))
px = img.load()
top, bottom = (28, 32, 92), (98, 54, 150)
for y in range(S):
    t = y / (S - 1)
    c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    for x in range(S):
        px[x, y] = c
d = ImageDraw.Draw(img)
# stars
for (x, y, r) in [(170, 180, 7), (300, 110, 5), (860, 150, 6), (900, 330, 4), (130, 420, 4), (780, 80, 4), (620, 160, 3)]:
    d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 246, 214))
# back card
card = Image.new("RGBA", (S, S), (0, 0, 0, 0))
cd = ImageDraw.Draw(card)
cd.rounded_rectangle([250, 300, 790, 860], radius=60, fill=(255, 255, 255, 90))
card = card.rotate(-8, resample=Image.BICUBIC, center=(520, 580))
img.paste(card, (0, 0), card)
# front card with shadow
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([232, 292, 772, 852], radius=60, fill=(0, 0, 0, 110))
shadow = shadow.filter(ImageFilter.GaussianBlur(18))
img.paste(shadow, (0, 12), shadow)
front = Image.new("RGBA", (S, S), (0, 0, 0, 0))
fd = ImageDraw.Draw(front)
fd.rounded_rectangle([232, 280, 772, 840], radius=60, fill=(250, 248, 255, 255))
# crescent moon on the card
fd.ellipse([372, 400, 632, 660], fill=(255, 196, 61, 255))
fd.ellipse([432, 360, 692, 620], fill=(250, 248, 255, 255))
# text lines
for i, w in enumerate([300, 220]):
    y = 712 + i * 50
    fd.rounded_rectangle([302, y, 302 + w, y + 22], radius=11, fill=(120, 110, 170, 255))
front = front.rotate(4, resample=Image.BICUBIC, center=(502, 560))
img.paste(front, (0, 0), front)
# "z z" sleep marks
for (x, y, s) in [(700, 300, 70), (790, 220, 52)]:
    d2 = ImageDraw.Draw(img)
    w = max(8, s // 7)
    d2.line([(x, y), (x + s, y)], fill=(255, 255, 255), width=w)
    d2.line([(x + s, y), (x, y + s)], fill=(255, 255, 255), width=w)
    d2.line([(x, y + s), (x + s, y + s)], fill=(255, 255, 255), width=w)
img.save(sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png")
