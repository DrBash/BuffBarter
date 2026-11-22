from PIL import Image
N = 32
img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
px = img.load()
# palette
OUT   = (24, 18, 14, 255)    # outline
FR1   = (120, 104, 82, 255)  # frame light
FR2   = (78, 66, 52, 255)    # frame dark
BG1   = (36, 58, 74, 255)    # background
BG2   = (30, 48, 62, 255)
G1    = (255, 236, 150, 255) # gold highlight
G2    = (240, 190, 70, 255)  # gold
G3    = (176, 116, 30, 255)  # gold shadow
INK   = (60, 34, 10, 255)
# frame
for y in range(N):
    for x in range(N):
        if x in (0, N-1) or y in (0, N-1):
            px[x, y] = OUT
        elif x in (1, 2) or y in (1, 2):
            px[x, y] = FR1
        elif x in (N-2, N-3) or y in (N-2, N-3):
            px[x, y] = FR2
        elif x == 3 or y == 3 or x == N-4 or y == N-4:
            px[x, y] = OUT
        else:
            # subtle dither so the background is not flat
            px[x, y] = BG1 if y < 16 else BG2
# chevrons: apex at (15.5, top), arm thickness 3
def chevron(top):
    for y in range(top, top + 10):
        d = y - top
        for x in range(4, N - 4):
            dx = abs(x - 15.5)
            if d - 3.5 <= dx - 0.5 <= d + 0.5 and dx <= 10.5:
                inner = dx - 0.5 - (d - 3.5)
                if inner < 1: c = G1
                elif inner < 3: c = G2
                else: c = G3
                px[x, y] = c
    # outline pass
for top in (7, 16):
    chevron(top)
# small cross sparkles
for (cx, cy) in ((7, 8), (24, 8)):
    for (ox, oy) in ((0,0),(1,0),(-1,0),(0,1),(0,-1)):
        px[cx+ox, cy+oy] = G1 if (ox, oy) == (0, 0) else G2
# dark outline around gold
src = img.copy(); sp = src.load()
gold = {G1, G2, G3}
for y in range(4, N-4):
    for x in range(4, N-4):
        if sp[x, y] in gold: continue
        for ox, oy in ((1,0),(-1,0),(0,1),(0,-1)):
            if sp[x+ox, y+oy] in gold:
                px[x, y] = INK; break
big = img.resize((384, 384), Image.NEAREST)
canvas = Image.new("RGBA", (400, 400), (0, 0, 0, 0))
canvas.paste(big, (8, 8))
canvas.save("variant_pixel.png")
