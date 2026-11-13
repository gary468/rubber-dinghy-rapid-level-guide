"""Draw the project logo (512x512 PNG): an orange rubber dinghy speeding along a numbered route.
Usage: python tools/make_logo.py <out.png>"""
import math, sys
from PIL import Image, ImageDraw, ImageFont

S = 512
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# background: rounded square, night sky to sea
bg = Image.new("RGBA", (S, S))
bd = ImageDraw.Draw(bg)
WATER = 250
for y in range(S):
    if y < WATER:
        t = y / WATER
        c = (int(14 + 18 * t), int(24 + 30 * t), int(52 + 40 * t), 255)
    else:
        t = (y - WATER) / (S - WATER)
        c = (int(16 + 6 * t), int(70 + 30 * t), int(120 + 30 * t), 255)
    bd.line([(0, y), (S, y)], fill=c)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=90, fill=255)
img.paste(bg, (0, 0), mask)
d = ImageDraw.Draw(img)

try:
    f_num = ImageFont.truetype("arialbd.ttf", 30)
    f_title = ImageFont.truetype("arialbd.ttf", 54)
except OSError:
    f_num = f_title = ImageFont.load_default()

# gold route from the dinghy's bow to three numbered stops on the sea
route = [(250, 238), (330, 300), (250, 360), (380, 405)]
d.line(route, fill=(255, 209, 0, 255), width=9, joint="curve")
for i, (x, y) in enumerate(route[1:], 1):
    d.ellipse([x - 23, y - 23, x + 23, y + 23], fill=(18, 18, 18, 255), outline=(255, 209, 0, 255), width=5)
    d.text((x, y + 1), str(i), font=f_num, fill=(255, 209, 0, 255), anchor="mm")

# wake behind the boat
for k, (y0, ln) in enumerate(((246, 120), (262, 90), (278, 60))):
    d.line([(150 - ln, y0), (150, y0 - 4)], fill=(220, 240, 255, 210 - k * 40), width=6)

# outboard motor at the stern
d.rectangle([128, 196, 150, 238], fill=(40, 40, 40, 255))
d.rectangle([136, 238, 144, 262], fill=(40, 40, 40, 255))

# dinghy: inflatable tube hull (rounded, bow lifted), seen side-on, sitting on the waterline
hull = [(150, 214), (262, 214), (282, 200), (290, 206), (276, 236), (250, 252), (162, 252), (150, 240)]
d.polygon(hull, fill=(255, 112, 30, 255), outline=(110, 38, 0, 255))
d.line(hull + [hull[0]], fill=(110, 38, 0, 255), width=5, joint="curve")
d.rounded_rectangle([166, 220, 258, 232], radius=6, fill=(255, 176, 100, 255))  # tube highlight

# waterline wave over the hull bottom
wave = [(x, WATER + 6 * math.sin(x / 22)) for x in range(40, S - 40, 4)]
d.line(wave, fill=(150, 210, 255, 220), width=5)

d.text((S // 2, 468), "RAPID LEVEL", font=f_title, fill=(255, 255, 255, 255), anchor="mm")
img.save(sys.argv[1])
print("saved", sys.argv[1])
