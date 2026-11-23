"""Builds the Godot Asset Store thumbnail (media/thumbnail.webp, 1920x1080) for the Kodogu add-on.

From the Kodogu repository root, with Pillow installed:

    python addons/godot/media/make_thumbnail.py <mascot render>         node_modules/@fontsource-variable/archivo/files/archivo-latin-wdth-normal.woff2         addons/godot/media/thumbnail.webp

The mascot render is prop 1's thumbnail on the site (its 1280.webp variant); colours are the
site's dark theme (apps/web/src/styles/tokens.css) and the logo is apps/web/public/favicon.svg.
"""
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

src, font_path, out = sys.argv[1], sys.argv[2], sys.argv[3]
W, H = 1920, 1080
BG = (31, 33, 37)          # the render's own backdrop
TEXT = (233, 233, 231)     # --text
MUTED = (178, 178, 172)
ACCENT = (255, 107, 44)    # --accent

img = Image.new("RGB", (W, H), BG)

# The mascot render, faded into the background at its edges.
m = Image.open(src).convert("RGB").resize((1180, 1180), Image.LANCZOS)
mask = Image.new("L", m.size, 0)
ImageDraw.Draw(mask).ellipse((90, 60, 1090, 1120), fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(90))
img.paste(m, (-20, -40), mask)

d = ImageDraw.Draw(img)

def font(size, weight):
    f = ImageFont.truetype(font_path, size)
    try:
        f.set_variation_by_axes([weight, 100])  # wght, wdth
    except Exception:
        try:
            f.set_variation_by_axes([weight])
        except Exception:
            pass
    return f

x = 1060
# The site's logo: three axes from one point.
cx, cy, s = x + 70, 300, 7.2
def P(px, py): return (cx + (px - 12) * s, cy + (py - 13) * s)
for (x2, y2), col in (((12, 3), (63, 163, 77)), ((21, 18), (229, 72, 77)), ((3, 18), (62, 123, 250))):
    d.line([P(12, 13), P(x2, y2)], fill=col, width=int(2.4 * s))
    ex, ey = P(x2, y2); r = 1.2 * s
    d.ellipse((ex - r, ey - r, ex + r, ey + r), fill=col)
r = 2.4 * s
d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=TEXT)

d.text((x, 420), "Kodogu", font=font(190, 700), fill=TEXT)
tag = font(56, 450)
d.text((x + 6, 650), "Free 3D props for Godot,", font=tag, fill=MUTED)
d.text((x + 6, 724), "found and installed in the editor.", font=tag, fill=MUTED)

pill = font(40, 600)
label = "Godot 4.7 add-on"
l, t, rr, b = d.textbbox((0, 0), label, font=pill)
px, py = x + 6, 846
d.rounded_rectangle((px, py, px + (rr - l) + 56, py + (b - t) + 36), radius=34, fill=ACCENT)
d.text((px + 28 - l, py + 18 - t), label, font=pill, fill=(22, 23, 26))

img.save(out, "WEBP", quality=90, method=6)
print(out, img.size)
