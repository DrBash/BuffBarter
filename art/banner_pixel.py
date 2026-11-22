from PIL import Image, ImageDraw, ImageFont
exec(open('pixel.py').read().split('big = img.resize')[0])   # builds 32x32 `img`
W, H = 300, 100
b = Image.new("RGBA", (W, H), (22, 32, 42, 255))
d = ImageDraw.Draw(b)
d.fontmode = "1"   # no anti-aliasing, crisp pixels
# subtle horizon band like the icon background
d.rectangle([0, 0, W, 46], fill=(30, 46, 60, 255))
# a few pixel stars
for (x, y) in ((120, 8), (214, 14), (282, 30), (150, 88), (262, 84), (96, 70)):
    d.point((x, y), fill=(240, 220, 160, 255))
# frame
d.rectangle([0, 0, W - 1, H - 1], outline=(24, 18, 14, 255))
d.rectangle([1, 1, W - 2, H - 2], outline=(120, 104, 82, 255))
d.rectangle([2, 2, W - 3, H - 3], outline=(78, 66, 52, 255))
# icon at 2x
icon = img.resize((64, 64), Image.NEAREST)
b.paste(icon, (14, 18), icon)
# title with a hard drop shadow
title = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 30)
d.text((92, 18), "Buff", font=title, fill=(60, 34, 10, 255))
d.text((90, 16), "Buff", font=title, fill=(240, 190, 70, 255))
bw = d.textlength("Buff", font=title)
d.text((92 + bw, 18), "Barter", font=title, fill=(10, 40, 60, 255))
d.text((90 + bw, 16), "Barter", font=title, fill=(130, 220, 255, 255))
tag = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 10)
d.text((91, 58), "Buff strangers. Get buffed back.", font=tag, fill=(232, 226, 210, 255))
d.text((91, 72), "for WoW Forever", font=tag, fill=(150, 160, 175, 255))
b.resize((W * 4, H * 4), Image.NEAREST).save("BuffBarter_banner_1200x400.png")
logo = img.resize((384, 384), Image.NEAREST)
c = Image.new("RGBA", (400, 400), (0, 0, 0, 0)); c.paste(logo, (8, 8))
c.save("BuffBarter_logo_400.png")
