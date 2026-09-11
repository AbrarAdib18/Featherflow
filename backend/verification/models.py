"""Registry for files uploaded during signup.

Each row links a privately-stored file (under ``private_media/``) to the account
that claimed it during registration. Before this table existed, uploaded files
were reachable only through the short-lived signed token and a fragile reverse
lookup across profile URL columns — so a file could end up orphaned (on disk,
referenced by nothing) or unreachable by its owner once the 2-hour grace window
closed.

The ``verification`` app is not schema-owned, so this table is created with an
ordinary Django migration (nothing in ``featherflow_schema.sql`` touches it).
"""
import uuid

from django.conf import settings
from django.db import models

DOCUMENT_TYPES = [
    ('profile_photo', 'Profile photo'),
    ('farm_photo', 'Farm photo'),
    ('council_proof', 'Council registration proof'),
    ('cv', 'CV / resume'),
    ('trade_license', 'Trade license'),
    ('business_registration_cert', 'Business registration certificate'),
    ('responsible_pharmacist_cert', 'Responsible pharmacist certificate'),
    ('license_photo', "Driver's license photo"),
    ('vehicle_photo', 'Vehicle photo'),
    ('proof_of_work', 'Proof of right to work'),
    ('ethics_certificate', 'Ethics certificate'),
    ('publications', 'Publications / portfolio'),
    ('id_document', 'ID document'),
    ('certificate', 'Certificate'),
    ('other', 'Other'),
]


class SignupDocument(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    # NULL while the file is still an anonymous upload (signup not finished).
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='signup_documents', null=True, blank=True)

    document_type = models.CharField(max_length=40, choices=DOCUMENT_TYPES, default='other')
    file_path = models.CharField(max_length=255, help_text='Path relative to private_media/.')
    token = models.TextField(unique=True, help_text='Signed access token (also embedded in the served URL).')
    content_type = models.CharField(max_length=100, blank=True)
    original_filename = models.CharField(max_length=255, blank=True)

    uploaded_at = models.DateTimeField()
    claimed_at = models.DateTimeField(null=True, blank=True)

    is_verified = models.BooleanField(default=False)
    verified_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='verified_signup_documents')
    verified_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'signup_documents'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', 'document_type']),
        ]

    def __str__(self):
        who = self.user_id or 'unclaimed'
        return f'{self.document_type} <{who}>'

    @property
    def url_path(self):
        return f'/api/auth/registration-documents/{self.token}/'
