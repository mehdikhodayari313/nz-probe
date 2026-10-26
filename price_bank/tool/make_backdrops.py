"""تصویرهای زمینه‌ی برنامه (نور سبز مه‌آلود با دانه‌ی فیلم) را می‌سازد.

زمینه به‌صورت تصویر آماده (JPEG) است، نه گرادیان Flutter: روی بعضی کارت‌های گرافیک ویندوز
گرادیانِ زنده سفید نمایش داده می‌شد، ولی تصویر همیشه درست دیده می‌شود.
الگو: «Living gradients» (Velaris) و صفحه‌ی Northline در 21st.dev.

اجرا: python3 -I tool/make_backdrops.py   (خروجی در assets/images/)
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'images')


def fbm(h, w, rng, octaves=4, base=3):
    """نویز نرم چندلایه (برای حرکت مه)."""
    acc = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        gh, gw = base * 2 ** o + 1, int((base * 2 ** o) * w / h) + 1
        g = (rng.random((gh, gw)) * 255).astype(np.uint8)
        im = Image.fromarray(g).resize((w, h), Image.BICUBIC)
        acc += amp * (np.asarray(im, np.float32) / 255.0)
        tot += amp
        amp *= 0.5
    return acc / tot


def blob(h, w, cx, cy, rx, ry):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    d = ((x - cx * w) / (rx * w)) ** 2 + ((y - cy * h) / (ry * h)) ** 2
    return np.exp(-d)


def render(w, h, seed, base, lights, fog_color, fog_amt, vignette, grain, out):
    rng = np.random.default_rng(seed)
    img = np.ones((h, w, 3), np.float32) * np.array(base, np.float32)
    warp = fbm(h, w, rng, 4, 2)
    for (cx, cy, rx, ry, col, k) in lights:
        m = blob(h, w, cx, cy, rx, ry) * (0.55 + 0.9 * warp)
        img += m[..., None] * np.array(col, np.float32) * k
    fog = fbm(h, w, rng, 5, 3)
    img += (fog ** 2)[..., None] * np.array(fog_color, np.float32) * fog_amt
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    r = np.sqrt(((x / w - 0.5) / 0.75) ** 2 + ((y / h - 0.5) / 0.75) ** 2)
    img *= (1 - vignette * np.clip(r, 0, 1.2) ** 2)[..., None]
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))
    a = np.asarray(im, np.float32) + rng.normal(0, grain, (h, w, 1)).astype(np.float32)
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(os.path.join(OUT, out), quality=86, optimize=True)
    print(out, os.path.getsize(os.path.join(OUT, out)) // 1024, 'KB')


def main():
    os.makedirs(OUT, exist_ok=True)
    # زمینه‌ی تیره‌ی کل برنامه: سبز زمردی کم‌نور از گوشه‌ها، مه ملایم، حاشیه‌ی تاریک
    render(1920, 1200, 7, (3, 7, 6), [
        (0.85, 0.05, 0.38, 0.34, (20, 120, 80), 0.62),
        (0.12, 0.92, 0.42, 0.38, (10, 85, 90), 0.48),
        (0.55, 0.60, 0.30, 0.25, (40, 110, 60), 0.12),
    ], (50, 120, 95), 0.10, 0.80, 3.0, 'backdrop_dark.jpg')
    # زمینه‌ی روشن: مه سبز-خاکستری بسیار ملایم
    render(1920, 1200, 11, (236, 243, 239), [
        (0.85, 0.05, 0.50, 0.40, (-20, 6, -10), 1.0),
        (0.10, 0.90, 0.55, 0.45, (-24, -4, -8), 0.9),
    ], (-18, -8, -12), 0.35, 0.06, 2.0, 'backdrop_light.jpg')
    # نوار معرفی داشبورد: نور سبز پررنگ‌تر و رگه‌ی لیمویی (Northline)
    render(1800, 560, 3, (3, 7, 6), [
        (0.30, 1.00, 0.42, 0.60, (30, 150, 85), 0.95),
        (0.08, 0.15, 0.22, 0.45, (10, 90, 95), 0.45),
        (0.52, 1.10, 0.18, 0.22, (120, 170, 40), 0.45),
    ], (60, 140, 100), 0.12, 0.70, 3.5, 'hero_dark.jpg')
    return 0


if __name__ == '__main__':
    sys.exit(main())
