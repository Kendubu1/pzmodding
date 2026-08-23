"""Rebuild the Fate Token artwork in place.

    python3 tools/fate_token_art.py

Writes straight over the mod's three images. Composed at 4x and downsampled, so
the edges stay clean at the sizes these are actually rendered: a small grid
thumbnail on the Workshop, a tab-sized icon in the mod list, and a larger poster
on the item page.

Palette is Project Zomboid's - desaturated green-grey and tarnished brass.

Needs Pillow: pip install pillow
"""
import math
import os
import random
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

random.seed(20260823)      # the art must come out the same every run

OUT = 512
SS = 4                      # supersample factor
S = OUT * SS

# Resolved from this file rather than the working directory, so the tool can be
# run from anywhere and still writes to the mod instead of wherever it was
# invoked.
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(ROOT, "PZMods", "PermadeathLock")

SERIF = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

BG_INNER = (34, 37, 33)
BG_OUTER = (11, 12, 11)
BRASS_LIT = (166, 141, 84)
BRASS_MID = (118, 97, 55)
BRASS_DARK = (72, 59, 33)
BRASS_DEEP = (37, 31, 18)
PATINA = (84, 104, 78)
RUST = (96, 62, 38)
INK = (204, 198, 180)
DIM = (124, 120, 108)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def radial_bg(size, inner, outer, power=1.35):
    """A soft vignette, built small and scaled up - it is smooth either way."""
    small = 192
    img = Image.new("RGB", (small, small))
    px = img.load()
    c = (small - 1) / 2.0
    longest = math.hypot(c, c)
    for y in range(small):
        for x in range(small):
            t = min(1.0, (math.hypot(x - c, y - c) / longest) ** power)
            px[x, y] = lerp(inner, outer, t)
    return img.resize((size, size), Image.BICUBIC)


def directional_shade(size, light, dark):
    """Top-left lit, bottom-right in shadow: one consistent light source."""
    small = 192
    img = Image.new("RGB", (small, small))
    px = img.load()
    for y in range(small):
        for x in range(small):
            t = ((x + y) / (2.0 * (small - 1))) ** 0.9
            px[x, y] = lerp(light, dark, t)
    return img.resize((size, size), Image.BICUBIC)


def circle_mask(size, box, blur=0):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse(box, fill=255)
    if blur:
        mask = mask.filter(ImageFilter.GaussianBlur(blur))
    return mask


def hourglass(size, cx, cy, w, h):
    """The motif. An hourglass reads at 32px where a skull turns to mush, and
    it is the right idea besides: the token buys you time, it does not make you
    immortal."""
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)

    half_w, half_h = w / 2.0, h / 2.0
    waist = w * 0.11
    cap = h * 0.055

    # The two bowls, meeting at a narrow waist.
    d.polygon([(cx - half_w, cy - half_h), (cx + half_w, cy - half_h),
               (cx + waist, cy), (cx - waist, cy)], fill=255)
    d.polygon([(cx - half_w, cy + half_h), (cx + half_w, cy + half_h),
               (cx + waist, cy), (cx - waist, cy)], fill=255)
    # Caps top and bottom, a shade wider than the bowls.
    for sign in (-1, 1):
        y = cy + sign * half_h
        d.rounded_rectangle([cx - half_w * 1.16, y - cap, cx + half_w * 1.16, y + cap],
                            radius=cap * 0.7, fill=255)
    return mask


def sand(size, cx, cy, w, h):
    """Sand in the lower bowl and a grain falling - the detail that stops it
    reading as a bow tie."""
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    half_w, half_h = w / 2.0, h / 2.0
    waist = w * 0.11

    pile = half_h * 0.44
    d.polygon([(cx - half_w * 0.80, cy + half_h * 0.88),
               (cx + half_w * 0.80, cy + half_h * 0.88),
               (cx + waist * 0.9, cy + half_h * 0.88 - pile),
               (cx - waist * 0.9, cy + half_h * 0.88 - pile)], fill=255)
    d.rectangle([cx - w * 0.022, cy + h * 0.02, cx + w * 0.022, cy + half_h * 0.42], fill=255)
    return mask


def milling(size, cx, cy, r, count=72, depth=None, width=None):
    """Rim notches. Coins have them; a plain disc looks like a button."""
    depth = depth or r * 0.055
    width = width or r * 0.017
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    for i in range(count):
        a = (i / count) * math.tau
        dx, dy = math.cos(a), math.sin(a)
        x0, y0 = cx + dx * (r - depth), cy + dy * (r - depth)
        x1, y1 = cx + dx * (r + depth * 0.15), cy + dy * (r + depth * 0.15)
        d.line([(x0, y0), (x1, y1)], fill=255, width=max(1, int(width)))
    return mask


def coin(size, cx, cy, r, worn=True):
    """One tarnished brass token on a transparent ground."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    box = (cx - r, cy - r, cx + r, cy + r)
    body = directional_shade(size, BRASS_LIT, BRASS_DEEP)
    layer.paste(body, (0, 0), circle_mask(size, box))

    # A cast shadow under it, so it sits on the ground rather than floating.
    shade = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    off = r * 0.05
    ImageDraw.Draw(shade).ellipse(
        (cx - r + off, cy - r + off * 1.6, cx + r + off, cy + r + off * 1.6),
        fill=(0, 0, 0, 150))
    shade = shade.filter(ImageFilter.GaussianBlur(r * 0.09))
    out = Image.alpha_composite(shade, layer)

    d = ImageDraw.Draw(out)

    # Rim: a bright outer edge and a recessed inner ring.
    d.ellipse(box, outline=BRASS_LIT + (210,), width=max(2, int(r * 0.035)))
    ir = r * 0.845
    d.ellipse((cx - ir, cy - ir, cx + ir, cy + ir),
              outline=BRASS_DEEP + (190,), width=max(2, int(r * 0.028)))

    # The recessed face is a touch darker than the rim.
    face_r = r * 0.80
    face = Image.new("RGBA", (size, size), BRASS_DARK + (90,))
    out = Image.alpha_composite(
        out, Image.composite(face, Image.new("RGBA", (size, size), (0, 0, 0, 0)),
                             circle_mask(size, (cx - face_r, cy - face_r,
                                                cx + face_r, cy + face_r), blur=r * 0.02)))

    mill = milling(size, cx, cy, r * 0.97)
    out = Image.alpha_composite(
        out, Image.composite(Image.new("RGBA", (size, size), BRASS_DEEP + (170,)),
                             Image.new("RGBA", (size, size), (0, 0, 0, 0)), mill))

    # The motif, cut in relief: a dark stamp with a lit edge below it.
    gw, gh = r * 0.72, r * 0.98
    glass = hourglass(size, cx, cy, gw, gh)
    lip = hourglass(size, cx, cy + r * 0.022, gw, gh)
    out = Image.alpha_composite(
        out, Image.composite(Image.new("RGBA", (size, size), BRASS_LIT + (120,)),
                             Image.new("RGBA", (size, size), (0, 0, 0, 0)), lip))
    out = Image.alpha_composite(
        out, Image.composite(Image.new("RGBA", (size, size), BRASS_DEEP + (235,)),
                             Image.new("RGBA", (size, size), (0, 0, 0, 0)), glass))
    grains = sand(size, cx, cy, gw, gh)
    out = Image.alpha_composite(
        out, Image.composite(Image.new("RGBA", (size, size), BRASS_LIT + (185,)),
                             Image.new("RGBA", (size, size), (0, 0, 0, 0)), grains))

    if worn:
        # Patina in the low corner. A pristine coin looks like a stock asset;
        # this one is meant to have been in somebody's pocket.
        patina = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        pd = ImageDraw.Draw(patina)
        for (ox, oy, pr, alpha, tone) in (
                (0.42, 0.46, 0.34, 120, PATINA), (0.28, 0.62, 0.24, 105, PATINA),
                (-0.50, 0.36, 0.20, 85, PATINA), (0.08, -0.54, 0.16, 70, RUST),
                (-0.34, -0.40, 0.18, 60, RUST), (0.56, -0.18, 0.15, 55, PATINA)):
            px_, py_ = cx + r * ox, cy + r * oy
            prr = r * pr
            pd.ellipse((px_ - prr, py_ - prr, px_ + prr, py_ + prr), fill=tone + (alpha,))
        patina = patina.filter(ImageFilter.GaussianBlur(r * 0.11))
        out = Image.alpha_composite(
            out, Image.composite(patina, Image.new("RGBA", (size, size), (0, 0, 0, 0)),
                                 circle_mask(size, box)))
        out = Image.alpha_composite(out, scratches(size, cx, cy, r * 0.92))

    return out


def grain(img, amount=0.10, scale=3):
    """Film grain over the whole frame.

    This is what separates a game asset from a logo: a perfectly smooth
    gradient reads as vector art, and nothing in Project Zomboid is smooth.
    Generated coarse and scaled up, so the speckle is visible at thumbnail size
    instead of vanishing in the downsample."""
    small = (max(1, img.width // scale), max(1, img.height // scale))
    noise = Image.effect_noise(small, 42).resize(img.size, Image.BILINEAR)
    noise = noise.filter(ImageFilter.GaussianBlur(0.6)).convert("RGB")
    return Image.blend(img.convert("RGB"), ImageChops.overlay(img.convert("RGB"), noise),
                       amount).convert("RGBA")


def scratches(size, cx, cy, r, count=26):
    """Wear on the face. A pristine coin looks like stock art; this one is
    meant to have been carried, spent and picked back up."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(count):
        a = random.uniform(0, math.tau)
        dist = r * math.sqrt(random.uniform(0, 0.86))
        x, y = cx + math.cos(a) * dist, cy + math.sin(a) * dist
        length = r * random.uniform(0.05, 0.30)
        angle = random.uniform(-0.5, 0.5) + math.pi * 0.25
        dx, dy = math.cos(angle) * length, math.sin(angle) * length
        light = random.random() < 0.55
        tone = BRASS_LIT if light else BRASS_DEEP
        d.line([(x - dx / 2, y - dy / 2), (x + dx / 2, y + dy / 2)],
               fill=tone + (random.randint(40, 95),),
               width=max(1, int(r * random.uniform(0.004, 0.011))))
    layer = layer.filter(ImageFilter.GaussianBlur(r * 0.004))
    return Image.composite(layer, Image.new("RGBA", (size, size), (0, 0, 0, 0)),
                           circle_mask(size, (cx - r, cy - r, cx + r, cy + r)))


def ground(size):
    return radial_bg(size, BG_INNER, BG_OUTER).convert("RGBA")


def text_at(img, xy, s, font, fill, anchor="mm", spacing=0):
    d = ImageDraw.Draw(img)
    if spacing:
        # Letter-spaced by hand: PIL has no tracking, and these titles want it.
        widths = [d.textlength(ch, font=font) for ch in s]
        total = sum(widths) + spacing * (len(s) - 1)
        x = xy[0] - total / 2.0
        for ch, w in zip(s, widths):
            d.text((x, xy[1]), ch, font=font, fill=fill, anchor="l" + anchor[1])
            x += w + spacing
    else:
        d.text(xy, s, font=font, fill=fill, anchor=anchor)


def save(img, path, size=OUT):
    img = grain(img)
    img.convert("RGB").resize((size, size), Image.LANCZOS).save(path, optimize=True)
    print("wrote %s %dx%d" % (os.path.relpath(path, ROOT), size, size))


# --- icon: the token alone, has to survive being shrunk to 32px -------------
icon = ground(S)
icon = Image.alpha_composite(icon, coin(S, S / 2, S / 2, S * 0.395))
# Smaller than the rest on purpose: the in-game mod list draws this at a size
# where half a megapixel is weight for nothing.
save(icon, os.path.join(MOD, "42", "icon.png"), size=128)

# --- preview: the storefront thumbnail, so it carries the name --------------
prev = ground(S)
prev = Image.alpha_composite(prev, coin(S, S / 2, S * 0.425, S * 0.300))

title = ImageFont.truetype(SERIF, int(S * 0.088))
sub = ImageFont.truetype(SANS, int(S * 0.0335))
text_at(prev, (S / 2, S * 0.790), "FATE TOKEN", title, INK + (255,), spacing=S * 0.006)
text_at(prev, (S / 2, S * 0.872), "MULTIPLAYER PERMADEATH", sub, DIM + (255,), spacing=S * 0.011)

save(prev, os.path.join(MOD, "preview.png"))

# --- poster: shown larger in the mod panel, so it can breathe ---------------
post = ground(S)
post = Image.alpha_composite(post, coin(S, S / 2, S * 0.400, S * 0.268))

ptitle = ImageFont.truetype(SERIF, int(S * 0.076))
pline = ImageFont.truetype(SANS, int(S * 0.0295))
text_at(post, (S / 2, S * 0.735), "FATE TOKEN", ptitle, INK + (255,), spacing=S * 0.0055)
text_at(post, (S / 2, S * 0.805), "One death, bought back.", pline, DIM + (255,))
text_at(post, (S / 2, S * 0.856), "Bind it to a place and wake there.", pline, DIM + (255,))
text_at(post, (S / 2, S * 0.925), "saint_kendrick", ImageFont.truetype(SANS, int(S * 0.026)),
        (92, 90, 84, 255), spacing=S * 0.006)
save(post, os.path.join(MOD, "42", "poster.png"))
