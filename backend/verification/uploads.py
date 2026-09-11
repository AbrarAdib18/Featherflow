"""Shared upload validation for images/documents.

Extracted from ``users.views.registration_upload`` so the anonymous signup
upload and the authenticated profile-photo endpoint enforce exactly the same
rules: allowed extension, advisory MIME, real magic bytes, and a size cap.
"""

MAX_UPLOAD_BYTES = 5 * 1024 * 1024

IMAGE_EXT = {'jpg', 'jpeg', 'png', 'webp'}
ALLOWED_EXT = IMAGE_EXT | {'pdf'}

# Canonical MIME types plus the aliases browsers / Flutter-web file pickers send.
ALLOWED_MIME = {
    'image/jpeg', 'image/jpg', 'image/pjpeg', 'image/png', 'image/x-png',
    'image/webp', 'application/pdf', 'application/x-pdf',
}
# A blank / octet-stream MIME is what Flutter web sends when no type is set —
# accepted as long as the extension + magic bytes agree.
GENERIC_MIME = {'', 'application/octet-stream', 'binary/octet-stream', None}

_MAGIC = {
    'jpg': (b'\xff\xd8\xff',),
    'jpeg': (b'\xff\xd8\xff',),
    'png': (b'\x89PNG\r\n\x1a\n',),
    'webp': (b'RIFF',),          # 'RIFF'....'WEBP'
    'pdf': (b'%PDF-',),
}


def sniff_ok(head, ext):
    sigs = _MAGIC.get(ext, ())
    if not sigs:
        return False
    if ext == 'webp':
        return head[:4] == b'RIFF' and head[8:12] == b'WEBP'
    return any(head.startswith(sig) for sig in sigs)


class UploadError(Exception):
    """Carries a user-facing message and an HTTP status."""

    def __init__(self, detail, status=400):
        super().__init__(detail)
        self.detail = detail
        self.status = status


def validate_upload(file, *, images_only=False, max_bytes=MAX_UPLOAD_BYTES):
    """Validate an ``UploadedFile``. Returns ``(ext, mime)`` or raises
    :class:`UploadError`. Leaves the file's read pointer at 0."""
    if file is None:
        raise UploadError('Choose a file to upload (form field "file").')

    mime = (file.content_type or '').lower().split(';')[0].strip()
    ext = file.name.rsplit('.', 1)[-1].lower() if '.' in file.name else ''

    if file.size > max_bytes:
        mb = file.size / (1024 * 1024)
        raise UploadError(
            f'That file is {mb:.1f} MB. The limit is '
            f'{max_bytes // (1024 * 1024)} MB — please choose a smaller file.')

    head = file.read(64)
    file.seek(0)

    allowed = IMAGE_EXT if images_only else ALLOWED_EXT
    ext_ok = ext in allowed
    sniff = sniff_ok(head, ext) if ext_ok else False
    mime_conflict = bool(mime) and mime not in ALLOWED_MIME and mime not in GENERIC_MIME

    if not ext_ok or not sniff or mime_conflict:
        if ext_ok and not sniff:
            raise UploadError(
                f'That file does not look like a valid {ext.upper()} file. '
                f'Re-export it and try again.')
        kinds = 'JPG, PNG or WebP' if images_only else 'JPG, PNG, WebP or PDF'
        raise UploadError(f'That file type is not supported. Upload a {kinds} file.')

    return ext, mime
