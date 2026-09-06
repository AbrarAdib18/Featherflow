class ExistingSchemaRouter:
    """Keep Django migrations away from tables owned by featherflow_schema.sql."""

    schema_owned_apps = {
        'users', 'subscriptions', 'payments', 'profiles', 'farms', 'workers',
        'feed', 'expenses', 'disease', 'chatbot', 'consultations', 'doctor', 'messaging',
        'pharmacy', 'delivery', 'community', 'articles', 'research', 'notifications', 'audit',
    }

    def allow_migrate(self, db, app_label, model_name=None, **hints):
        if app_label in self.schema_owned_apps:
            return False
        return None
