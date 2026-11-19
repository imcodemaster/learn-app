"""
Image upload hardening. Every uploaded image is decoded and re-encoded with
Pillow: this strips metadata (EXIF/GPS) and anything hidden inside the file,
and rejects files that are not real images.
"""

from __future__ import annotations

import io
import secrets

from PIL import Image, ImageOps, UnidentifiedImageError

ALLOWED_FORMATS = {"JPEG": "jpg", "PNG": "png", "WEBP": "webp", "GIF": "png"}
MAX_SOURCE_PIXELS = 4000 * 4000


class ImageRejected(ValueError):
    pass


def sanitize_image_bytes(data: bytes, max_side: int = 1600) -> tuple[bytes, str]:
    """Returns (clean_bytes, extension). Raises ImageRejected for bad input."""
    try:
        with Image.open(io.BytesIO(data)) as probe:
            fmt = (probe.format or "").upper()
            width, height = probe.size
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        raise ImageRejected("Upload a valid JPG, PNG, WebP or GIF image.") from exc
    if fmt not in ALLOWED_FORMATS:
        raise ImageRejected("Only JPG, PNG, WebP or GIF images are allowed.")
    if width < 1 or height < 1 or width * height > MAX_SOURCE_PIXELS:
        raise ImageRejected("Image dimensions are too large (max 4000 × 4000).")

    try:
        with Image.open(io.BytesIO(data)) as img:
            img.load()
            img = ImageOps.exif_transpose(img)
            if fmt == "GIF":
                img.seek(0)
            has_alpha = img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info)
            img = img.convert("RGBA" if has_alpha else "RGB")
            img.thumbnail((max_side, max_side))
            out = io.BytesIO()
            ext = ALLOWED_FORMATS[fmt]
            if ext == "jpg" and not has_alpha:
                img.save(out, format="JPEG", quality=85, optimize=True)
            elif ext == "webp":
                img.save(out, format="WEBP", quality=85)
            else:
                ext = "png"
                img.save(out, format="PNG", optimize=True)
    except (OSError, ValueError) as exc:
        raise ImageRejected("Could not read this image. Try another file.") from exc
    return out.getvalue(), ext


def random_image_name(prefix: str, ext: str) -> str:
    return f"{prefix}/{secrets.token_hex(16)}.{ext}"
