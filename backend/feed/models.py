from django.db import models

# TODO: implement models for the feed app based on featherflow_schema.sql

class Placeholder(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        abstract = True
