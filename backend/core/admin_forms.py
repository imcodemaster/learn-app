"""Admin form helpers shared by several apps."""

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.files.base import ContentFile
from django.core.files.uploadedfile import UploadedFile

from .images import ImageRejected, sanitize_image_bytes


def sanitize_uploaded_image(file, max_side: int = 1600):
    """Re-encodes a newly uploaded image; leaves existing/cleared values untouched."""
    if not isinstance(file, UploadedFile):
        return file
    if file.size and file.size > settings.MAX_IMAGE_UPLOAD_BYTES:
        limit_mb = settings.MAX_IMAGE_UPLOAD_BYTES // (1024 * 1024)
        raise ValidationError(f"Image is too large (maximum {limit_mb} MB).")
    file.seek(0)
    try:
        clean_bytes, ext = sanitize_image_bytes(file.read(), max_side=max_side)
    except ImageRejected as exc:
        raise ValidationError(str(exc)) from exc
    return ContentFile(clean_bytes, name=f"upload.{ext}")
