#!/usr/bin/env python3
"""투두락 앱 아이콘 — 노래방 미러볼(목업 concept-noraebang 톤).
상단중앙 보라 라디얼 배경 + 작고 또렷한 컬러 보케 점 여러 개 + 중앙 네온 '락' + 링."""
import math, random, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops, ImageOps

S = 2
SZ = 1024
N = SZ * S
cx = cy = N // 2
FONT = "TodoLock/Resources/Fonts/NanumMyeongjo-ExtraBold.ttf"
random.seed(11)

def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

# ── 팔레트 (목업 disco dot 색) ──
C0 = (0x2A, 0x1A, 0x4A)   # 상단 보라
C1 = (0x15, 0x0F, 0x2A)
C2 = (0x0C, 0x0A, 0x14)   # 하단 어두움
CORE  = (0xEC, 0xFB, 0xFF)
NEON  = (0x2F, 0x9B, 0xFF)
NEON2 = (0x3D, 0xE8, 0xFF)
BLACK = (0, 0, 0)
DOTS = [(0xFF,0x3B,0x6B),(0x2F,0x7B,0xFF),(0x2F,0xE2,0x7B),
        (0xFF,0xD2,0x3B),(0xB1,0x3B,0xFF),(0x38,0xE8,0xE8),
        (0xFF,0x8A,0x2F),(0xFF,0x3B,0xC8)]   # 6 주황 7 마젠타

# ── 상단중앙 보라 라디얼 배경 (저해상→확대) ──
def radial_bg():
    G = 256
    im = Image.new("RGB", (G, G))
    px = im.load()
    ox, oy = G / 2, 0.0
    maxd = math.hypot(G / 2, G)
    for yy in range(G):
        for xx in range(G):
            dd = math.hypot(xx - ox, yy - oy) / maxd
            if dd < 0.45:
                c = lerp(C0, C1, dd / 0.45)
            else:
                c = lerp(C1, C2, min((dd - 0.45) / 0.55, 1.0))
            px[xx, yy] = c
    return im.resize((N, N), Image.BILINEAR)

img = radial_bg()

# ── 미러볼 보케: 거울조각 모양(마름모·사각·길쭉) 다양하게 ──
def blob(drw, x, y, r, fill, asp=1.0, rot=0.0, irr=0.05, npts=48):
    # 거의 원형 + 살짝 길쭉(회전 타원). 뾰족함 없이 완만한 둘레 변주만.
    ca, sa = math.cos(rot), math.sin(rot)
    pts = []
    for k in range(npts):
        ang = k / npts * 2 * math.pi
        rr = r * (1 + math.sin(ang * 2 + rot) * irr)  # 완만한 1~2개 lobe
        ex = math.cos(ang) * rr
        ey = math.sin(ang) * rr * asp                 # asp>1 → 길쭉
        pts.append((x + ex * ca - ey * sa, y + ex * sa + ey * ca))
    drw.polygon(pts, fill=fill)

# 색 인덱스: 0핑크 1파랑 2초록 3노랑 4보라 5청록 6주황 7마젠타
# ── BIG↔MID 사이: 소프트하지만 색 또렷한 보케 ~8개, 랜덤 들쭉날쭉 ──
# 크기 중간대(노이즈 같은 잔점 없음) · 블러 중간(부드런 가장자리) · 은은한 코어
SEED  = int(os.environ.get("SCATTER_SEED", "6"))
NDOTS = int(os.environ.get("SCATTER_N", "8"))
rnd = random.Random(SEED)

dots = []
last_ci = -1
for _ in range(NDOTS):
    fx = rnd.uniform(0.07, 0.93)
    fy = rnd.uniform(0.07, 0.93)
    big = rnd.random() < 0.40
    r0   = rnd.uniform(74, 104) if big else rnd.uniform(44, 64)   # 중대형
    blur = rnd.uniform(20, 30) if big else rnd.uniform(11, 18)    # 중간 흐림
    ci = rnd.randrange(len(DOTS))
    while ci == last_ci:
        ci = rnd.randrange(len(DOTS))
    last_ci = ci
    asp = rnd.uniform(1.0, 1.30)
    rot = rnd.uniform(0, math.pi)
    dots.append((fx, fy, r0, ci, blur, asp, rot))

for fx, fy, r0, ci, blur, asp, rot in sorted(dots, key=lambda d: -d[2]):
    x, y = fx * N, fy * N
    col = DOTS[ci]
    layer = Image.new("RGB", (N, N), BLACK)
    blob(ImageDraw.Draw(layer), x, y, r0 * S, col, asp, rot)
    layer = layer.filter(ImageFilter.GaussianBlur(blur * S))
    img = ImageChops.screen(img, layer)
    img = ImageChops.screen(img, layer)
    # 은은한 밝은 코어 → 색 또렷 + 깊이 (wash처럼 죽지 않게)
    core = Image.new("RGB", (N, N), BLACK)
    blob(ImageDraw.Draw(core), x, y, r0 * S * 0.46,
         lerp(col, (255, 255, 255), 0.35), asp, rot)
    core = core.filter(ImageFilter.GaussianBlur(blur * 0.55 * S))
    img = ImageChops.screen(img, core)

# ── 약한 비네팅 ──
vig = Image.new("L", (N, N), 0)
vr = int(N * 0.55)
ImageDraw.Draw(vig).ellipse([cx - vr, cy - vr, cx + vr, cy + vr], fill=255)
vig = vig.filter(ImageFilter.GaussianBlur(int(N * 0.13)))
img = ImageChops.multiply(img, Image.merge("RGB", (vig, vig, vig)))

def add_glow(base, mask, color, blurs):
    for b in blurs:
        g = mask.filter(ImageFilter.GaussianBlur(b))
        base = ImageChops.screen(base, ImageOps.colorize(g, BLACK, color))
    return base

# ── 네온 링 ──
ring = Image.new("L", (N, N), 0)
R = int(SZ * 0.40) * S
ImageDraw.Draw(ring).ellipse([cx - R, cy - R, cx + R, cy + R], outline=255, width=13 * S)
img = add_glow(img, ring, NEON,  [26 * S, 13 * S])
img = add_glow(img, ring, NEON2, [6 * S])
ring_core = ImageOps.colorize(ring.filter(ImageFilter.GaussianBlur(2 * S)), BLACK, CORE)
img = ImageChops.screen(img, ring_core)

# ── '락' 글자 ──
def fit_font(text, target_px):
    f = ImageFont.truetype(FONT, 100)
    bb = f.getbbox(text)
    return ImageFont.truetype(FONT, int(100 * target_px / (bb[3] - bb[1])))

text = "락"
font = fit_font(text, int(R * 1.08))
bb = font.getbbox(text)
tx = cx - (bb[2] - bb[0]) / 2 - bb[0]
ty = cy - (bb[3] - bb[1]) / 2 - bb[1]
glyph = Image.new("L", (N, N), 0)
ImageDraw.Draw(glyph).text((tx, ty), text, font=font, fill=255, stroke_width=11 * S, stroke_fill=255)

img = add_glow(img, glyph, NEON,  [30 * S, 18 * S])
img = add_glow(img, glyph, NEON2, [10 * S, 4 * S])
core = ImageOps.colorize(glyph.filter(ImageFilter.GaussianBlur(2.5 * S)), BLACK, CORE)
img = ImageChops.screen(img, core)
core2 = ImageOps.colorize(glyph.filter(ImageFilter.GaussianBlur(1 * S)), BLACK, CORE)
img = ImageChops.screen(img, core2)

# ── 저장 ──
final = img.resize((SZ, SZ), Image.LANCZOS)
out = "TodoLock/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
final.save(out)
final.save("/Users/hime/Desktop/todolock-icon-mid.png")
print("saved", out, "+ ~/Desktop/todolock-icon-mid.png")
