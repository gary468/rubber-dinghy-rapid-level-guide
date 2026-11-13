"""Make the in-game textures (needs Pillow; run without -I so user site-packages load):
    python tools/make_media.py
- media/area_fill.tga, media/area_edge.tga: 16x16 quest-area textures in the route's gold
  (the fill is a flat colour; the edge fades from a bright rim at the top row to clear)
- media/duck.png: 512x512 rubber duck on a dark-blue rounded square (logo / icon art)
- media/icon.tga: 64x64 minimap/settings/AddOns-list icon made from the duck
"""
import math, pathlib
from PIL import Image, ImageDraw

root = pathlib.Path(__file__).resolve().parent.parent
media = root / "media"

GOLD, RIM = (255, 200, 40), (255, 223, 130)
Image.new("RGBA", (16, 16), GOLD + (255,)).save(media / "area_fill.tga")
edge = Image.new("RGBA", (16, 16))
for y in range(16):
    t = y / 15.0
    a = int(238 * (1 - t) ** 2.5)
    c = tuple(int(RIM[i] + (GOLD[i] - RIM[i]) * t) for i in range(3))
    for x in range(16):
        edge.putpixel((x, y), c + (a,))
edge.save(media / "area_edge.tga")


def duck(S=512):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bg = Image.new("RGBA", (S, S))
    bd = ImageDraw.Draw(bg)
    for y in range(S):
        t = y / S
        bd.line([(0, y), (S, y)], fill=(int(16 + 10 * t), int(40 + 50 * t), int(80 + 70 * t), 255))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=96, fill=255)
    img.paste(bg, (0, 0), mask)
    d = ImageDraw.Draw(img)
    YEL, YEL_D, ORA, ORA_D, OUT = (255, 214, 40), (235, 170, 20), (255, 140, 30), (205, 90, 10), (120, 70, 0)
    # tail, body, wing
    d.polygon([(92, 300), (60, 228), (150, 262)], fill=YEL, outline=OUT)
    d.ellipse([80, 236, 400, 430], fill=YEL, outline=OUT, width=8)
    d.ellipse([140, 290, 300, 380], fill=YEL_D)
    d.arc([140, 290, 300, 380], 200, 340, fill=OUT, width=6)
    # head
    d.ellipse([250, 96, 430, 276], fill=YEL, outline=OUT, width=8)
    # beak (upper + lower)
    d.polygon([(410, 168), (488, 186), (412, 206)], fill=ORA, outline=ORA_D)
    d.polygon([(412, 206), (478, 206), (414, 226)], fill=ORA_D)
    # eye with highlight
    d.ellipse([345, 140, 381, 176], fill=(20, 20, 20))
    d.ellipse([360, 146, 372, 158], fill=(255, 255, 255))
    # cheek blush
    d.ellipse([318, 196, 352, 220], fill=(255, 170, 60))
    # water
    wave = [(x, 420 + 10 * math.sin(x / 26)) for x in range(0, S + 4, 4)]
    d.polygon(wave + [(S, S), (0, S)], fill=(70, 150, 230, 255))
    d.line(wave, fill=(200, 235, 255), width=8)
    # keep everything inside the rounded square
    from PIL import ImageChops
    img.putalpha(ImageChops.multiply(img.getchannel("A"), mask))
    return img


art = duck()
art.save(media / "duck.png")
art.resize((64, 64), Image.LANCZOS).save(media / "icon.tga")
print("wrote", [p.name for p in sorted(media.glob("*")) if p.suffix in (".tga", ".png")])
