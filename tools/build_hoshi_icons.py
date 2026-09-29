"""Render matching desktop and Android launcher icons for Hoshi."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SIZE = 1024
SCALE = SIZE / 256


def px(value: float) -> int:
    return round(value * SCALE)


def box(x0: float, y0: float, x1: float, y1: float) -> tuple[int, ...]:
    return px(x0), px(y0), px(x1), px(y1)


def star(draw: ImageDraw.ImageDraw, x: float, y: float, r: float, color: str) -> None:
    draw.polygon(
        [
            (px(x), px(y - r)),
            (px(x + r * 0.24), px(y - r * 0.24)),
            (px(x + r), px(y)),
            (px(x + r * 0.24), px(y + r * 0.24)),
            (px(x), px(y + r)),
            (px(x - r * 0.24), px(y + r * 0.24)),
            (px(x - r), px(y)),
            (px(x - r * 0.24), px(y - r * 0.24)),
        ],
        fill=color,
    )


def render_art() -> Image.Image:
    art = Image.new("RGBA", (SIZE, SIZE))
    draw = ImageDraw.Draw(art)

    # A broad crescent remains readable in the 16-pixel Windows taskbar icon.
    moon = Image.new("L", art.size)
    moon_draw = ImageDraw.Draw(moon)
    moon_draw.ellipse(box(68, 45, 188, 165), fill=255)
    moon_draw.ellipse(box(105, 28, 216, 139), fill=0)
    glow = Image.new("RGBA", art.size, (247, 216, 160, 0))
    glow.putalpha(moon.filter(ImageFilter.GaussianBlur(px(8))))
    art.alpha_composite(glow)
    gold = Image.new("RGBA", art.size, (247, 216, 160, 0))
    gold.putalpha(moon)
    art.alpha_composite(gold)

    draw = ImageDraw.Draw(art)
    star(draw, 180, 65, 13, "#fff9e9")
    star(draw, 47, 75, 6, "#f4d7a7")
    star(draw, 204, 123, 6, "#f4d7a7")
    for x, y, r in ((56, 126, 2), (211, 45, 2), (197, 174, 2), (92, 30, 2)):
        draw.ellipse(box(x - r, y - r, x + r, y + r), fill="#fff4de")

    # Rounded clouds frame the moon without turning the small icon into a blur.
    draw.ellipse(box(28, 160, 109, 236), fill="#cdc2dc")
    draw.ellipse(box(72, 141, 161, 238), fill="#e9ddea")
    draw.ellipse(box(137, 164, 222, 238), fill="#d3c6e1")
    draw.rounded_rectangle(box(28, 196, 224, 241), radius=px(19), fill="#e9ddea")
    draw.arc(box(77, 147, 158, 227), 191, 311, fill="#fff8f0", width=px(3))

    return art


def render_desktop() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(box(13, 14, 243, 244), radius=px(54), fill=(32, 24, 52, 125))
    shadow = shadow.filter(ImageFilter.GaussianBlur(px(9)))
    image.alpha_composite(shadow)

    mask = Image.new("L", image.size)
    ImageDraw.Draw(mask).rounded_rectangle(box(12, 9, 244, 241), radius=px(55), fill=255)
    sky = Image.new("RGBA", image.size)
    sky_pixels = sky.load()
    for y in range(SIZE):
        t = y / (SIZE - 1)
        color = (
            round(67 + 48 * t),
            round(62 + 40 * t),
            round(100 + 48 * t),
            255,
        )
        for x in range(SIZE):
            sky_pixels[x, y] = color
    sky.putalpha(mask)
    image.alpha_composite(sky)

    image.alpha_composite(render_art())
    # Keep the icon edge crisp on both bright and dark desktops.
    border = Image.new("RGBA", image.size)
    ImageDraw.Draw(border).rounded_rectangle(
        box(12, 9, 244, 241), radius=px(55), outline=(255, 247, 233, 150), width=px(2)
    )
    image.alpha_composite(border)
    return image.resize((256, 256), Image.Resampling.LANCZOS)


def render_android_foreground() -> Image.Image:
    # Android can mask the 108 dp canvas to a circle, squircle or rounded square.
    # Keep the artwork within its central 72 dp so no moon or cloud gets cut off.
    canvas = Image.new("RGBA", (432, 432))
    canvas.alpha_composite(render_art().resize((324, 324), Image.Resampling.LANCZOS), (54, 54))
    return canvas


if __name__ == "__main__":
    icon = render_desktop()
    destination = ROOT / "assets"
    icon.save(destination / "hoshi_desktop.png")
    icon.save(
        destination / "hoshi_desktop.ico",
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    android = ROOT / "android" / "app" / "src" / "main" / "res" / "drawable-xxxhdpi"
    android.mkdir(parents=True, exist_ok=True)
    render_android_foreground().save(android / "ic_launcher_foreground.png")
