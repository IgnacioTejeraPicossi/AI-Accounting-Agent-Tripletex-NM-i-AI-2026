from __future__ import annotations

from copy import deepcopy
from typing import Any


def should_retry_validation_error(error_message: str, payload: dict[str, Any] | None) -> bool:
    if not payload:
        return False

    message = (error_message or "").lower()

    retry_hints = [
        "validation",
        "invalid",
        "unknown field",
        "cannot deserialize",
        "expected",
        "bad request",
    ]
    return any(hint in message for hint in retry_hints)


def normalize_payload_for_retry(path: str, payload: dict[str, Any] | None) -> dict[str, Any] | None:
    if not payload:
        return payload

    cleaned = _remove_empty_values(deepcopy(payload))

    if "/employee" in path:
        cleaned = _normalize_employee_payload(cleaned)

    if "/invoice" in path or "/order" in path:
        cleaned = _normalize_invoice_payload(cleaned)

    return cleaned


def _remove_empty_values(value: Any) -> Any:
    if isinstance(value, dict):
        result = {}
        for k, v in value.items():
            cleaned = _remove_empty_values(v)
            if cleaned in ("", None, [], {}):
                continue
            result[k] = cleaned
        return result

    if isinstance(value, list):
        result = []
        for item in value:
            cleaned = _remove_empty_values(item)
            if cleaned in ("", None, [], {}):
                continue
            result.append(cleaned)
        return result

    return value


def _normalize_employee_payload(payload: dict[str, Any]) -> dict[str, Any]:
    if "phone" in payload and "mobileNumber" not in payload:
        payload["mobileNumber"] = payload.pop("phone")
    return payload


def _normalize_invoice_payload(payload: dict[str, Any]) -> dict[str, Any]:
    lines = payload.get("orderLines")
    if isinstance(lines, list):
        for line in lines:
            if "count" in line and isinstance(line["count"], str):
                try:
                    line["count"] = int(line["count"])
                except ValueError:
                    pass
            if "unitPrice" in line and isinstance(line["unitPrice"], str):
                try:
                    line["unitPrice"] = float(line["unitPrice"])
                except ValueError:
                    pass
    return payload
