import json
import logging
import sys
from datetime import datetime, timezone
from typing import Any


def get_logger(name: str) -> logging.Logger:
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger

    logger.setLevel(logging.INFO)
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(handler)
    logger.propagate = False
    return logger


def log_event(logger: logging.Logger, event_name: str, **fields: Any) -> None:
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "event": event_name,
        **_sanitize_fields(fields),
    }
    logger.info(json.dumps(payload, ensure_ascii=False))


def _sanitize_fields(fields: dict[str, Any]) -> dict[str, Any]:
    redacted_keys = {"session_token", "authorization", "password"}
    clean = {}
    for key, value in fields.items():
        if key.lower() in redacted_keys:
            clean[key] = "***REDACTED***"
        else:
            clean[key] = value
    return clean
