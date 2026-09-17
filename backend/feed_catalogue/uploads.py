"""Public catalogue image storage for feed companies/products.

These images (company logos/covers, product photos) are intentionally
public — farmers need to see them in the marketplace, unlike the private
verification documents in ``verification/documents.py``. Reuses
``verification.uploads.validate_upload`` for the same real
extension+size+magic-byte checks used everywhere else in this backend
(rather than the weaker inline checks some other public-image endpoints in
this codebase use), and Django's default public storage
(``MEDIA_ROOT``/``MEDIA_URL``) the same way ``community.views.upload`` and
``pharmacy.catalogue_views._store_image`` already do — no new storage
mechanism invented.
"""
import io
import uuid

from django.conf import settings
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage

from verification.uploads import UploadError, validate_upload  # noqa: F401  (re-exported)


def generate_placeholder_image(label, *, color=(46, 125, 50), size=(640, 400)):
    """Renders a simple labelled PNG and saves it under MEDIA_ROOT, returning
    an absolute public URL. Used only by the demo seed command — real
    uploads always go through ``store_public_image`` instead. Exists so demo
    products/companies have an image that actually loads in the running app
    rather than a fake/placeholder URL that 404s (Pillow is already a
    dependency for the disease-detection ML pipeline, so this adds none)."""
    from PIL import Image, ImageDraw, ImageFont

    img = Image.new('RGB', size, color)
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype('arial.ttf', 28)
    except OSError:
        font = ImageFont.load_default()
    bbox = draw.textbbox((0, 0), label, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(((size[0] - tw) / 2, (size[1] - th) / 2), label, fill='white', font=font)

    buffer = io.BytesIO()
    img.save(buffer, format='PNG')
    path = default_storage.save(f'feed_demo/{uuid.uuid4().hex}.png', ContentFile(buffer.getvalue()))
    return f'{settings.PUBLIC_BASE_URL}{default_storage.url(path)}'


def store_public_image(request, file, prefix):
    """Validate ``file`` and persist it under ``MEDIA_ROOT/{prefix}/``.
    Returns the absolute public URL. Raises ``UploadError`` on failure —
    nothing is written to storage or the database in that case."""
    ext, _mime = validate_upload(file, images_only=True)
    path = default_storage.save(f'{prefix}/{uuid.uuid4().hex}.{ext}', ContentFile(file.read()))
    return request.build_absolute_uri(default_storage.url(path))


def delete_public_image(url):
    """Best-effort cleanup of a previously-stored image, given the absolute
    URL a prior ``store_public_image`` call returned. Never raises — a
    failed cleanup just leaves an orphaned file, which is preferable to
    ever deleting the *new* image or blocking the request that replaced it."""
    if not url:
        return
    try:
        idx = url.index(settings.MEDIA_URL)
    except ValueError:
        return
    rel_path = url[idx + len(settings.MEDIA_URL):]
    try:
        if default_storage.exists(rel_path):
            default_storage.delete(rel_path)
    except Exception:
        pass
