"""Make the in-game textures (needs Pillow; run without -I so user site-packages load):
    python tools/make_media.py
- media/area_fill.tga, media/area_edge.tga: 16x16 quest-area textures in the route's gold
  (the fill is a flat colour; the edge fades from a bright rim at the top row to clear)
- media/icon.tga: 64x64 minimap/settings icon cut from media/logo.png
"""
import pathlib
from PIL import Image

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

logo = Image.open(media / "logo.png").convert("RGBA")
logo.resize((64, 64), Image.LANCZOS).save(media / "icon.tga")
print("wrote", [p.name for p in sorted(media.glob("*.tga"))])
