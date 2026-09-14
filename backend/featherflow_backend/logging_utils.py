"""Structured JSON log formatter — opt in with FF_LOG_FORMAT=json.

Kept deliberately dependency-free (stdlib ``json`` only) rather than pulling
in python-json-logger, so it works with nothing beyond what's already in
requirements.txt.
"""
import json
import logging


class JSONLogFormatter(logging.Formatter):
    def format(self, record):
        payload = {
            'timestamp': self.formatTime(record, '%Y-%m-%dT%H:%M:%S%z'),
            'level': record.levelname,
            'logger': record.name,
            'message': record.getMessage(),
            'request_id': getattr(record, 'request_id', '-'),
        }
        if record.exc_info:
            payload['exception'] = self.formatException(record.exc_info)
        # Anything passed via logger.info(..., extra={...}) beyond the
        # standard LogRecord attributes rides along too.
        standard = logging.makeLogRecord({}).__dict__.keys()
        for key, value in record.__dict__.items():
            if key not in standard and key not in payload:
                try:
                    json.dumps(value)
                except TypeError:
                    value = str(value)
                payload[key] = value
        return json.dumps(payload, default=str)
