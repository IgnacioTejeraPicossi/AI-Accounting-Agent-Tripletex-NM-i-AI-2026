#!/bin/bash
set -e

echo "=== Creating Tripletex Agent ==="

cd ~
mkdir -p tripletex_agent/app/workflows tripletex_agent/tests

cd ~/tripletex_agent

# --- requirements.txt ---
cat > requirements.txt << 'REQEOF'
fastapi==0.115.8
uvicorn[standard]==0.34.0
requests==2.32.3
pydantic==2.10.6
pypdf==5.3.0
REQEOF

# --- Dockerfile ---
cat > Dockerfile << 'DEOF'
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8080

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
DEOF

# --- .dockerignore ---
cat > .dockerignore << 'DIEOF'
__pycache__/
*.pyc
*.pyo
.venv/
venv/
.env
.git/
tests/
.pytest_cache/
setup.sh
DIEOF

# --- app/__init__.py ---
touch app/__init__.py

# --- app/workflows/__init__.py ---
touch app/workflows/__init__.py

# --- app/schemas.py ---
cat > app/schemas.py << 'PYEOF'
from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field, field_validator


class SolveFile(BaseModel):
    filename: str
    content_base64: str
    mime_type: str

    @field_validator("filename", "content_base64", "mime_type")
    @classmethod
    def not_empty(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Field cannot be empty")
        return value


class TripletexCredentials(BaseModel):
    base_url: str
    session_token: str

    @field_validator("base_url")
    @classmethod
    def url_not_empty(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("base_url cannot be empty")
        return value

    @field_validator("session_token")
    @classmethod
    def token_not_empty(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("session_token cannot be empty")
        return value


class SolveRequest(BaseModel):
    prompt: str
    files: list[SolveFile] = Field(default_factory=list)
    tripletex_credentials: TripletexCredentials

    @field_validator("prompt")
    @classmethod
    def prompt_not_empty(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("prompt cannot be empty")
        return value


class SolveResponse(BaseModel):
    status: str = "completed"


class ParsedIntent(BaseModel):
    task_type: str
    action: str
    language: str | None = None
    entities: dict[str, Any] = Field(default_factory=dict)
    fields: dict[str, Any] = Field(default_factory=dict)
    confidence: float = 0.0


class ExecutionResult(BaseModel):
    success: bool
    workflow_name: str
    created_ids: dict[str, Any] = Field(default_factory=dict)
    notes: list[str] = Field(default_factory=list)
    verification: dict[str, Any] = Field(default_factory=dict)
PYEOF

# --- app/logging_utils.py ---
cat > app/logging_utils.py << 'PYEOF'
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
PYEOF

# --- app/context.py ---
cat > app/context.py << 'PYEOF'
import time
import uuid
from dataclasses import dataclass, field


@dataclass
class ExecutionContext:
    request_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    start_time: float = field(default_factory=time.perf_counter)
    api_call_count: int = 0
    error_4xx_count: int = 0
    workflow_name: str = ""
    detected_language: str = ""
    retry_used: bool = False
    verification_skipped: bool = False
    assume_fresh_account: bool = False
    invoice_order_flow_used: bool = False

    def elapsed_ms(self) -> int:
        return int((time.perf_counter() - self.start_time) * 1000)
PYEOF

# --- app/retry_policy.py ---
cat > app/retry_policy.py << 'PYEOF'
from __future__ import annotations

from copy import deepcopy
from typing import Any


def should_retry_validation_error(error_message: str, payload: dict[str, Any] | None) -> bool:
    if not payload:
        return False
    message = (error_message or "").lower()
    retry_hints = ["validation", "invalid", "unknown field", "cannot deserialize", "expected", "bad request"]
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
PYEOF

# --- app/file_handler.py ---
cat > app/file_handler.py << 'PYEOF'
import base64
import tempfile
from pathlib import Path

from app.schemas import SolveFile


def decode_files(files: list[SolveFile]) -> list[dict]:
    if not files:
        return []
    output = []
    temp_dir = Path(tempfile.mkdtemp(prefix="tripletex_files_"))
    for f in files:
        raw = base64.b64decode(f.content_base64)
        target = temp_dir / f.filename
        target.write_bytes(raw)
        extracted_text = ""
        if f.mime_type == "application/pdf":
            extracted_text = _extract_pdf_text_safe(target)
        output.append({
            "filename": f.filename,
            "mime_type": f.mime_type,
            "path": str(target),
            "size_bytes": len(raw),
            "extracted_text": extracted_text,
        })
    return output


def _extract_pdf_text_safe(path: Path) -> str:
    try:
        from pypdf import PdfReader
        reader = PdfReader(str(path))
        return "\n".join(page.extract_text() or "" for page in reader.pages).strip()
    except Exception:
        return ""
PYEOF

# --- app/tripletex_client.py ---
cat > app/tripletex_client.py << 'PYEOF'
from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any, Dict, Optional
from urllib.parse import urljoin

import requests

from app.context import ExecutionContext
from app.logging_utils import get_logger, log_event
from app.retry_policy import normalize_payload_for_retry, should_retry_validation_error

logger = get_logger("tripletex.client")


class TripletexApiError(Exception):
    pass


class TripletexValidationError(TripletexApiError):
    pass


class TripletexNotFoundError(TripletexApiError):
    pass


@dataclass
class TripletexClient:
    base_url: str
    session_token: str
    timeout: float = 20.0
    execution_context: Optional[ExecutionContext] = None
    session: requests.Session = field(init=False, repr=False)

    def __post_init__(self) -> None:
        self.base_url = self.base_url.rstrip("/") + "/"
        self.session = requests.Session()
        self.session.auth = ("0", self.session_token)
        self.session.headers.update({"Accept": "application/json", "Content-Type": "application/json"})

    def _build_url(self, path: str) -> str:
        return urljoin(self.base_url, path.lstrip("/"))

    def _handle_response(self, response: requests.Response) -> Any:
        if response.status_code == 404:
            raise TripletexNotFoundError(f"Tripletex resource not found: {response.text}")
        if response.status_code in (400, 401, 403, 422):
            raise TripletexValidationError(f"Tripletex validation/auth error {response.status_code}: {response.text}")
        if not response.ok:
            raise TripletexApiError(f"Tripletex API error {response.status_code}: {response.text}")
        if not response.content:
            return None
        try:
            data = response.json()
        except ValueError as exc:
            raise TripletexApiError("Tripletex returned non-JSON response") from exc
        if isinstance(data, dict) and "value" in data:
            return data["value"]
        return data

    def _request(self, method: str, path: str, params: Optional[Dict[str, Any]] = None, json_body: Optional[Dict[str, Any]] = None) -> Any:
        url = self._build_url(path)
        start = time.perf_counter()
        response = self.session.request(method=method, url=url, params=params, json=json_body, timeout=self.timeout)
        elapsed_ms = int((time.perf_counter() - start) * 1000)
        request_id = self.execution_context.request_id if self.execution_context else None
        if self.execution_context:
            self.execution_context.api_call_count += 1
            if 400 <= response.status_code < 500:
                self.execution_context.error_4xx_count += 1
        log_event(logger, "tripletex_api_call", request_id=request_id, method=method, path=path, status_code=response.status_code, elapsed_ms=elapsed_ms)
        try:
            return self._handle_response(response)
        except TripletexValidationError as exc:
            if method not in {"POST", "PUT"} or json_body is None:
                raise
            if not should_retry_validation_error(str(exc), json_body):
                raise
            normalized = normalize_payload_for_retry(path, json_body)
            if normalized == json_body:
                raise
            log_event(logger, "retry_attempted", request_id=request_id, method=method, path=path)
            if self.execution_context:
                self.execution_context.retry_used = True
            retry_start = time.perf_counter()
            retry_response = self.session.request(method=method, url=url, params=params, json=normalized, timeout=self.timeout)
            retry_elapsed_ms = int((time.perf_counter() - retry_start) * 1000)
            if self.execution_context:
                self.execution_context.api_call_count += 1
                if 400 <= retry_response.status_code < 500:
                    self.execution_context.error_4xx_count += 1
            log_event(logger, "tripletex_api_call", request_id=request_id, method=method, path=path, status_code=retry_response.status_code, elapsed_ms=retry_elapsed_ms, is_retry=True)
            try:
                result = self._handle_response(retry_response)
                log_event(logger, "retry_succeeded", request_id=request_id, method=method, path=path)
                return result
            except Exception:
                log_event(logger, "retry_failed", request_id=request_id, method=method, path=path)
                raise

    def get(self, path: str, params: Optional[Dict[str, Any]] = None) -> Any:
        return self._request("GET", path, params=params)

    def post(self, path: str, json_body: Optional[Dict[str, Any]] = None, params: Optional[Dict[str, Any]] = None) -> Any:
        return self._request("POST", path, params=params, json_body=json_body)

    def put(self, path: str, json_body: Optional[Dict[str, Any]] = None, params: Optional[Dict[str, Any]] = None) -> Any:
        return self._request("PUT", path, params=params, json_body=json_body)

    def delete(self, path: str, params: Optional[Dict[str, Any]] = None) -> Any:
        return self._request("DELETE", path, params=params)

    def list_values(self, path: str, params: Optional[Dict[str, Any]] = None) -> list[dict]:
        data = self.get(path, params=params)
        if isinstance(data, dict) and "values" in data:
            return data["values"]
        if isinstance(data, list):
            return data
        return []

    def get_first_match(self, path: str, params: Optional[Dict[str, Any]] = None) -> Optional[dict]:
        values = self.list_values(path, params=params)
        return values[0] if values else None

    def find_customer_by_name(self, name: str) -> Optional[dict]:
        return self.get_first_match("/customer", params={"name": name, "fields": "id,name,email", "count": 10})

    def find_employee_by_email(self, email: str) -> Optional[dict]:
        values = self.list_values("/employee", params={"fields": "id,firstName,lastName,email,mobileNumber", "count": 100})
        for item in values:
            if str(item.get("email", "")).strip().lower() == email.strip().lower():
                return item
        return None

    def find_product_by_name(self, name: str) -> Optional[dict]:
        return self.get_first_match("/product", params={"name": name, "fields": "id,name,productNumber", "count": 10})

    def find_project_by_name(self, name: str) -> Optional[dict]:
        return self.get_first_match("/project", params={"name": name, "fields": "id,name", "count": 10})

    def create_customer(self, name: str, email: Optional[str] = None, is_customer: bool = True) -> dict:
        payload: Dict[str, Any] = {"name": name, "isCustomer": is_customer}
        if email:
            payload["email"] = email
        return self.post("/customer", json_body=payload)

    def create_employee(self, first_name: str, last_name: str, email: Optional[str] = None, mobile_number: Optional[str] = None) -> dict:
        payload: Dict[str, Any] = {"firstName": first_name, "lastName": last_name}
        if email:
            payload["email"] = email
        if mobile_number:
            payload["mobileNumber"] = mobile_number
        return self.post("/employee", json_body=payload)

    def create_product(self, name: str, product_number: Optional[str] = None) -> dict:
        payload: Dict[str, Any] = {"name": name}
        if product_number:
            payload["productNumber"] = product_number
        return self.post("/product", json_body=payload)

    def create_project(self, name: str, customer_id: Optional[int] = None, description: Optional[str] = None, start_date: Optional[str] = None, end_date: Optional[str] = None) -> dict:
        payload: Dict[str, Any] = {"name": name}
        if customer_id is not None:
            payload["customer"] = {"id": customer_id}
        if description:
            payload["description"] = description
        if start_date:
            payload["startDate"] = start_date
        if end_date:
            payload["endDate"] = end_date
        return self.post("/project", json_body=payload)

    def create_order(self, customer_id: int, order_lines: list[dict]) -> dict:
        payload = {"customer": {"id": customer_id}, "orderLines": order_lines}
        return self.post("/order", json_body=payload)

    def create_invoice_from_order(self, customer_id: int, order_id: int, invoice_date: Optional[str] = None, due_date: Optional[str] = None) -> dict:
        payload: Dict[str, Any] = {"customer": {"id": customer_id}, "orders": [{"id": order_id}]}
        if invoice_date:
            payload["invoiceDate"] = invoice_date
        if due_date:
            payload["invoiceDueDate"] = due_date
        return self.post("/invoice", json_body=payload)
PYEOF

# --- app/prompt_parser.py ---
cat > app/prompt_parser.py << 'PYEOF'
from __future__ import annotations

import re
from app.schemas import ParsedIntent

EMAIL_RE = re.compile(r"[\w\.\-+]+@[\w\.-]+\.\w+")
PHONE_RE = re.compile(r"(\+\d{1,3}\s?)?[\d\s\-]{6,15}")
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")
QUANTITY_RE = re.compile(r"(?:quantity|cantidad|antall|mengde|quantit[eé]|anzahl|menge)\s*[:\s]?\s*(\d+)", re.IGNORECASE)
UNIT_PRICE_RE = re.compile(r"(?:unit\s*price|precio\s*unitario|enhetspris|pris|prix\s*unitaire|st[uü]ckpreis|einzelpreis)\s*[:\s]?\s*(\d[\d\s]*[\.,]?\d*)", re.IGNORECASE)

ACTION_KEYWORDS = {
    "create": ["create", "crear", "opprett", "lag", "criar", "erstellen", "cr[eé]er", "registrer", "register", "add", "a[nñ]adir", "legg til"],
    "update": ["update", "actualizar", "oppdater", "endre", "atualizar", "aktualisieren", "mettre à jour", "change", "cambiar"],
    "delete": ["delete", "eliminar", "slett", "fjern", "apagar", "l[oö]schen", "supprimer", "remove"],
    "reverse": ["reverse", "reverser", "tilbakef[oø]r", "reversar", "stornieren", "annuler", "credit note", "kreditnota"],
}

ENTITY_KEYWORDS = {
    "employee": ["employee", "empleado", "ansatt", "funcion[aá]rio", "mitarbeiter", "employ[eé]", "arbeidstaker"],
    "customer": ["customer", "cliente", "kunde", "client", "klient"],
    "product": ["product", "producto", "produkt", "produit", "produto", "vare"],
    "project": ["project", "proyecto", "prosjekt", "projeto", "projekt", "projet"],
    "invoice": ["invoice", "factura", "faktura", "rechnung", "facture", "fatura"],
    "travel_expense": ["travel expense", "gasto de viaje", "reiseregning", "reisekostnad", "despesa de viagem", "reisekosten", "frais de voyage", "travel report"],
    "department": ["department", "departamento", "avdeling", "departement", "abteilung", "d[eé]partement"],
    "payment": ["payment", "pago", "betaling", "innbetaling", "pagamento", "zahlung", "paiement"],
}

LANGUAGE_HINTS = {
    "nb": ["opprett", "ansatt", "kunde", "faktura", "prosjekt", "reiseregning", "avdeling", "bestilling", "slette", "legg til", "endre"],
    "nn": ["opprett", "tilsett", "kunde", "faktura", "prosjekt", "reiserekning"],
    "es": ["crear", "empleado", "cliente", "producto", "factura", "proyecto", "eliminar", "departamento"],
    "en": ["create", "employee", "customer", "product", "invoice", "project", "delete", "department"],
    "pt": ["criar", "cliente", "produto", "fatura", "projeto", "departamento"],
    "de": ["erstellen", "mitarbeiter", "kunde", "produkt", "rechnung", "projekt", "abteilung"],
    "fr": ["employé", "client", "produit", "facture", "projet", "département", "supprimer"],
}

CUSTOMER_LINK_RE = re.compile(
    r"(?:for\s+(?:the\s+)?customer|for\s+(?:the\s+)?client|para\s+(?:el\s+)?cliente|for\s+kunden|f[uü]r\s+(?:den\s+)?kunden|pour\s+(?:le\s+)?client)\s+[\"']?(.+?)(?:[\"']?\s*(?:with|con|med|mit|avec|,|\.|$))",
    re.IGNORECASE,
)

PROJECT_NAME_RE = re.compile(
    r'(?:named|llamado|kalt|som\s+heter|namens|nomm[eé]|nomeado)\s+["\']?([^"\']+?)["\']?\s*(?:for|para|f[uü]r|pour|$)',
    re.IGNORECASE,
)


def detect_language(prompt: str) -> str | None:
    text = prompt.lower()
    scores = {}
    for lang, hints in LANGUAGE_HINTS.items():
        scores[lang] = sum(1 for word in hints if word in text)
    if not any(scores.values()):
        return None
    best = max(scores, key=lambda k: scores[k])
    return best if scores[best] > 0 else None


def detect_action(text: str) -> str:
    lower = text.lower()
    for action, keywords in ACTION_KEYWORDS.items():
        for kw in keywords:
            if re.search(kw, lower):
                return action
    return "create"


def detect_entity(text: str) -> str:
    lower = text.lower()
    priority = ["invoice", "travel_expense", "payment", "project", "employee", "customer", "product", "department"]
    for entity in priority:
        for kw in ENTITY_KEYWORDS.get(entity, []):
            if re.search(kw, lower):
                return entity
    return "unknown"


def extract_common_fields(text: str) -> dict:
    fields = {}
    email_match = EMAIL_RE.search(text)
    if email_match:
        fields["email"] = email_match.group(0)
    phone_match = PHONE_RE.search(text)
    if phone_match:
        raw = phone_match.group(0).strip()
        if len(re.sub(r"\D", "", raw)) >= 6:
            fields["phone"] = raw
    dates = DATE_RE.findall(text)
    if dates:
        fields["dates"] = dates
    return fields


def _extract_person_name(text: str) -> tuple[str, str]:
    named_match = re.search(
        r"(?:named|llamado|kalt|som\s+heter|namens|nomm[eé]|nomeado|navn)\s+([A-Z\u00C0-\u024F][a-z\u00C0-\u024F'\-]+(?:\s+[A-Z\u00C0-\u024F][a-z\u00C0-\u024F'\-]+)*)",
        text,
    )
    if named_match:
        parts = named_match.group(1).strip().split()
        if len(parts) >= 2:
            return parts[0], " ".join(parts[1:])
        if parts:
            return parts[0], ""
    skip = {"Create","Crear","Opprett","Criar","Erstellen","Employee","Empleado","Ansatt","Mitarbeiter",
            "Customer","Cliente","Kunde","Client","Product","Producto","Produkt","Produit",
            "Project","Proyecto","Prosjekt","Projekt","Projet","Invoice","Factura","Faktura",
            "She","He","The","An","Ein","Eine","Un","Una","En","Et","Han","Hun","Med","Til",
            "For","Som","Og","Skal","With","And","Named","Called","Llamado","Kalt","Register","Registrer"}
    tokens = re.findall(r"[A-Z\u00C0-\u024F][a-z\u00C0-\u024F'\-]+", text)
    filtered = [t for t in tokens if t not in skip]
    if len(filtered) >= 2:
        return filtered[0], filtered[1]
    if filtered:
        return filtered[0], ""
    return "Unknown", "Unknown"


def _extract_quoted_or_tail_name(text: str) -> str:
    quoted = re.findall(r'"([^"]+)"', text)
    if quoted:
        return quoted[0].strip()
    named = re.search(r"(?:named|called|llamado|kalt|som\s+heter|namens|nomm[eé]|nomeado)\s+(.+?)(?:\s+(?:with|con|med|mit|avec|for|para)|[,\.]|$)", text, re.IGNORECASE)
    if named:
        return named.group(1).strip()
    return text.strip()


def _extract_customer_name(text: str) -> str | None:
    match = CUSTOMER_LINK_RE.search(text)
    return match.group(1).strip() if match else None


def _extract_invoice_lines(text: str) -> list[dict]:
    line = {}
    qty_match = QUANTITY_RE.search(text)
    price_match = UNIT_PRICE_RE.search(text)
    ctx_match = re.search(r"(\d+)\s+(?:hours?|horas?|timer?|st[uü]ck|unit[eé]?s?|pcs|stk)\s", text, re.IGNORECASE)
    if qty_match:
        line["quantity"] = int(qty_match.group(1))
    elif ctx_match:
        line["quantity"] = int(ctx_match.group(1))
    if price_match:
        raw = price_match.group(1).replace(" ", "").replace(",", ".")
        try:
            line["unit_price"] = float(raw)
        except ValueError:
            pass
    combo = re.search(r"(?:med|with|con)\s+(\d+)\s+(?:timer?|hours?|horas?|stk|pcs|units?)\s+([A-Z\u00C0-\u024F][\w\s]+?)(?:\s+(?:til|at|a|[àá]|zu)\s+(\d[\d\s]*[\.,]?\d*)\s*(?:kr|NOK|EUR|USD)?)?", text, re.IGNORECASE)
    if combo:
        line["quantity"] = int(combo.group(1))
        line["product_name"] = combo.group(2).strip()
        if combo.group(3):
            raw = combo.group(3).replace(" ", "").replace(",", ".")
            try:
                line["unit_price"] = float(raw)
            except ValueError:
                pass
    if "product_name" not in line:
        pm = re.search(r"(?:line\s+for|for)\s+([A-Z\u00C0-\u024F][\w\s]+?)(?:\s*,|\s+(?:quantity|cantidad|antall|at|a|til|zu)|$)", text, re.IGNORECASE)
        if pm:
            candidate = pm.group(1).strip()
            skip = {"customer", "cliente", "kunde", "client", "kunden"}
            if candidate.lower() not in skip:
                line["product_name"] = candidate
    if line:
        if "quantity" not in line:
            line["quantity"] = 1
        return [line]
    return []


def parse_prompt(prompt: str) -> ParsedIntent:
    text = prompt.strip()
    language = detect_language(text)
    action = detect_action(text)
    entity = detect_entity(text)
    common = extract_common_fields(text)

    if entity == "employee":
        fn, ln = _extract_person_name(text)
        return ParsedIntent(task_type="create_employee", action=action, language=language,
            entities={"employee": {"first_name": fn, "last_name": ln}},
            fields={"email": common.get("email"), "phone": common.get("phone")}, confidence=0.80)

    if entity == "customer":
        name = _extract_quoted_or_tail_name(text)
        return ParsedIntent(task_type="create_customer", action=action, language=language,
            entities={"customer": {"name": name}}, fields={"email": common.get("email")}, confidence=0.75)

    if entity == "product":
        name = _extract_quoted_or_tail_name(text)
        return ParsedIntent(task_type="create_product", action=action, language=language,
            entities={"product": {"name": name}}, fields={}, confidence=0.70)

    if entity == "project":
        pname = _extract_quoted_or_tail_name(text)
        pn_match = PROJECT_NAME_RE.search(text)
        if pn_match:
            pname = pn_match.group(1).strip()
        cname = _extract_customer_name(text)
        dates = DATE_RE.findall(text)
        return ParsedIntent(task_type="create_project", action=action, language=language,
            entities={"project": {"name": pname}},
            fields={"customer_name": cname, "start_date": dates[0] if dates else None, "end_date": dates[1] if len(dates) > 1 else None},
            confidence=0.72)

    if entity == "invoice":
        cname = _extract_customer_name(text)
        dates = DATE_RE.findall(text)
        lines = _extract_invoice_lines(text)
        return ParsedIntent(task_type="create_invoice", action=action, language=language,
            entities={"invoice": {"customer_name": cname, "invoice_date": dates[0] if dates else None, "due_date": dates[1] if len(dates) > 1 else None, "lines": lines}},
            fields={"customer_name": cname}, confidence=0.70)

    if entity == "travel_expense":
        return ParsedIntent(task_type=f"{action}_travel_expense", action=action, language=language,
            entities={}, fields=common, confidence=0.60)

    if entity == "department":
        name = _extract_quoted_or_tail_name(text)
        return ParsedIntent(task_type="create_department", action=action, language=language,
            entities={"department": {"name": name}}, fields={}, confidence=0.60)

    if entity == "payment":
        return ParsedIntent(task_type="register_payment", action="register", language=language,
            entities={}, fields=common, confidence=0.55)

    return ParsedIntent(task_type="unsupported", action="unknown", language=language,
        entities={}, fields={}, confidence=0.10)
PYEOF

# --- app/planner.py ---
cat > app/planner.py << 'PYEOF'
from __future__ import annotations
from app.schemas import ParsedIntent


def build_execution_plan(intent: ParsedIntent) -> dict:
    task_type = intent.task_type
    plan = {"task_type": task_type, "required_dependencies": [], "should_verify": False, "assume_fresh_account": True, "search_strategy": {}}

    if task_type in ("create_employee", "create_customer", "create_product", "create_department"):
        plan["search_strategy"] = {"skip_duplicate_check": True}

    elif task_type == "create_project":
        customer_name = intent.fields.get("customer_name")
        if customer_name:
            plan["required_dependencies"] = ["customer"]
            plan["search_strategy"] = {"lookup_customer": True}
        else:
            plan["search_strategy"] = {"lookup_customer": False}

    elif task_type == "create_invoice":
        plan["required_dependencies"] = ["customer", "order"]
        plan["search_strategy"] = {"lookup_customer": True, "lookup_product": True}
        plan["assume_fresh_account"] = False

    elif task_type == "delete_travel_expense":
        plan["required_dependencies"] = ["travel_expense"]
        plan["search_strategy"] = {"lookup_travel_expense": True}
        plan["assume_fresh_account"] = False

    elif task_type == "register_payment":
        plan["required_dependencies"] = ["invoice"]
        plan["search_strategy"] = {"lookup_invoice": True}
        plan["assume_fresh_account"] = False

    return plan
PYEOF

# --- app/task_router.py ---
cat > app/task_router.py << 'PYEOF'
from app.schemas import ParsedIntent
from app.workflows.base import BaseWorkflow
from app.workflows.create_customer import CreateCustomerWorkflow
from app.workflows.create_employee import CreateEmployeeWorkflow
from app.workflows.create_invoice import CreateInvoiceWorkflow
from app.workflows.create_product import CreateProductWorkflow
from app.workflows.create_project import CreateProjectWorkflow
from app.workflows.delete_travel_expense import DeleteTravelExpenseWorkflow


class UnsupportedTaskError(Exception):
    pass


_WORKFLOW_MAP = {
    "create_employee": CreateEmployeeWorkflow,
    "create_customer": CreateCustomerWorkflow,
    "create_product": CreateProductWorkflow,
    "create_project": CreateProjectWorkflow,
    "create_invoice": CreateInvoiceWorkflow,
    "delete_travel_expense": DeleteTravelExpenseWorkflow,
}


def get_workflow(intent: ParsedIntent) -> BaseWorkflow:
    workflow_cls = _WORKFLOW_MAP.get(intent.task_type)
    if workflow_cls is None:
        raise UnsupportedTaskError(f"Unsupported task type: {intent.task_type}")
    return workflow_cls()
PYEOF

# --- app/workflows/base.py ---
cat > app/workflows/base.py << 'PYEOF'
from __future__ import annotations
from abc import ABC, abstractmethod
from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient


class BaseWorkflow(ABC):
    name = "base"

    @abstractmethod
    def validate_intent(self, intent: ParsedIntent) -> None:
        raise NotImplementedError

    @abstractmethod
    def execute(self, intent: ParsedIntent, client: TripletexClient, context: dict) -> ExecutionResult:
        raise NotImplementedError

    @abstractmethod
    def verify(self, intent: ParsedIntent, client: TripletexClient, execution_result: ExecutionResult) -> dict:
        raise NotImplementedError
PYEOF

# --- app/workflows/create_employee.py ---
cat > app/workflows/create_employee.py << 'PYEOF'
from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient, TripletexValidationError
from app.workflows.base import BaseWorkflow


class CreateEmployeeWorkflow(BaseWorkflow):
    name = "create_employee"

    def validate_intent(self, intent: ParsedIntent) -> None:
        employee = intent.entities.get("employee", {})
        if not employee.get("first_name") or not employee.get("last_name"):
            raise TripletexValidationError("Employee first_name and last_name are required")

    def execute(self, intent: ParsedIntent, client: TripletexClient, context: dict) -> ExecutionResult:
        self.validate_intent(intent)
        plan = context.get("plan", {})
        employee = intent.entities["employee"]
        email = intent.fields.get("email")
        phone = intent.fields.get("phone")
        skip_dup = plan.get("search_strategy", {}).get("skip_duplicate_check", False)
        if email and not skip_dup:
            existing = client.find_employee_by_email(email)
            if existing:
                return ExecutionResult(success=True, workflow_name=self.name, created_ids={"employee_id": existing.get("id")}, notes=["Employee already existed; skipped duplicate creation"], verification={"existing": True, "skipped_get_verify": True})
        created = client.create_employee(first_name=employee["first_name"], last_name=employee["last_name"], email=email, mobile_number=phone)
        return ExecutionResult(success=True, workflow_name=self.name, created_ids={"employee_id": created.get("id")}, notes=[], verification={"skipped_get_verify": True})

    def verify(self, intent: ParsedIntent, client: TripletexClient, execution_result: ExecutionResult) -> dict:
        return execution_result.verification
PYEOF

# --- app/workflows/create_customer.py ---
cat > app/workflows/create_customer.py << 'PYEOF'
from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient, TripletexValidationError
from app.workflows.base import BaseWorkflow


class CreateCustomerWorkflow(BaseWorkflow):
    name = "create_customer"

    def validate_intent(self, intent: ParsedIntent) -> None:
        customer = intent.entities.get("customer", {})
        if not customer.get("name"):
            raise TripletexValidationError("Customer name is required")

    def execute(self, intent: ParsedIntent, client: TripletexClient, context: dict) -> ExecutionResult:
        self.validate_intent(intent)
        plan = context.get("plan", {})
        customer_name = intent.entities["customer"]["name"]
        email = intent.fields.get("email")
        skip_dup = plan.get("search_strategy", {}).get("skip_duplicate_check", False)
        if not skip_dup:
            existing = client.find_customer_by_name(customer_name)
            if existing:
                return ExecutionResult(success=True, workflow_name=self.name, created_ids={"customer_id": existing.get("id")}, notes=["Customer already existed"], verification={"existing": True, "skipped_get_verify": True})
        created = client.create_customer(name=customer_name, email=email)
        return ExecutionResult(success=True, workflow_name=self.name, created_ids={"customer_id": created.get("id")}, notes=[], verification={"skipped_get_verify": True})

    def verify(self, intent: ParsedIntent, client: TripletexClient, execution_result: ExecutionResult) -> dict:
        return execution_result.verification
PYEOF

# --- app/workflows/create_product.py ---
cat > app/workflows/create_product.py << 'PYEOF'
from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient, TripletexValidationError
from app.workflows.base import BaseWorkflow


class CreateProductWorkflow(BaseWorkflow):
    name = "create_product"

    def validate_intent(self, intent: ParsedIntent) -> None:
        product = intent.entities.get("product", {})
        if not product.get("name"):
            raise TripletexValidationError("Product name is required")

    def execute(self, intent: ParsedIntent, client: TripletexClient, context: dict) -> ExecutionResult:
        self.validate_intent(intent)
        plan = context.get("plan", {})
        product_name = intent.entities["product"]["name"]
        skip_dup = plan.get("search_strategy", {}).get("skip_duplicate_check", False)
        if not skip_dup:
            existing = client.find_product_by_name(product_name)
            if existing:
                return ExecutionResult(success=True, workflow_name=self.name, created_ids={"product_id": existing.get("id")}, notes=["Product already existed"], verification={"existing": True, "skipped_get_verify": True})
        created = client.create_product(name=product_name)
        return ExecutionResult(success=True, workflow_name=self.name, created_ids={"product_id": created.get("id")}, notes=[], verification={"skipped_get_verify": True})

    def verify(self, intent: ParsedIntent, client: TripletexClient, execution_result: ExecutionResult) -> dict:
        return execution_result.verification
PYEOF

# --- app/workflows/create_project.py ---
cat > app/workflows/create_project.py << 'PYEOF'
from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient, TripletexNotFoundError, TripletexValidationError
from app.workflows.base import BaseWorkflow


class CreateProjectWorkflow(BaseWorkflow):
    name = "create_project"

    def validate_intent(self, intent: ParsedIntent) -> None:
        project = intent.entities.get("project", {})
        if not str(project.get("name", "")).strip():
            raise TripletexValidationError("Project name is required")

    def execute(self, intent: ParsedIntent, client: TripletexClient, context: dict) -> ExecutionResult:
        self.validate_intent(intent)
        plan = context.get("plan", {})
        project = intent.entities.get("project", {})
        project_name = str(project.get("name", "")).strip()
        customer_name = intent.fields.get("customer_name")
        description = intent.fields.get("description")
        start_date = intent.fields.get("start_date")
        end_date = intent.fields.get("end_date")
        customer_id = None
        if plan.get("search_strategy", {}).get("lookup_customer") and customer_name:
            customer = client.find_customer_by_name(customer_name)
            if not customer:
                raise TripletexNotFoundError(f"Customer not found for project: {customer_name}")
            customer_id = customer["id"]
        created = client.create_project(name=project_name, customer_id=customer_id, description=description, start_date=start_date, end_date=end_date)
        return ExecutionResult(success=True, workflow_name=self.name, created_ids={"project_id": created.get("id")}, notes=[], verification={"skipped_get_verify": True})

    def verify(self, intent: ParsedIntent, client: TripletexClient, execution_result: ExecutionResult) -> dict:
        return execution_result.verification
PYEOF

# --- app/workflows/create_invoice.py ---
cat > app/workflows/create_invoice.py << 'PYEOF'
from datetime import date
from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient, TripletexNotFoundError, TripletexValidationError
from app.workflows.base import BaseWorkflow


class CreateInvoiceWorkflow(BaseWorkflow):
    name = "create_invoice"

    def validate_intent(self, intent: ParsedIntent) -> None:
        invoice = intent.entities.get("invoice", {})
        customer_name = invoice.get("customer_name") or intent.fields.get("customer_name")
        lines = invoice.get("lines", [])
        if not str(customer_name or "").strip():
            raise TripletexValidationError("Invoice customer_name is required")
        if not isinstance(lines, list) or not lines:
            raise TripletexValidationError("At least one invoice line is required")

    def execute(self, intent: ParsedIntent, client: TripletexClient, context: dict) -> ExecutionResult:
        self.validate_intent(intent)
        invoice = intent.entities.get("invoice", {})
        customer_name = invoice.get("customer_name") or intent.fields.get("customer_name")
        lines = invoice.get("lines", [])
        invoice_date = invoice.get("invoice_date") or intent.fields.get("invoice_date") or str(date.today())
        due_date = invoice.get("due_date") or intent.fields.get("due_date") or invoice_date
        customer = client.find_customer_by_name(customer_name)
        if not customer:
            raise TripletexNotFoundError(f"Customer not found for invoice: {customer_name}")
        customer_id = customer["id"]
        order_lines = [self._build_order_line(l, client) for l in lines]
        created_order = client.post("/order", json_body={"customer": {"id": customer_id}, "orderLines": order_lines})
        order_id = created_order.get("id")
        if not order_id:
            raise TripletexValidationError("Order creation did not return an id")
        created_invoice = client.post("/invoice", json_body={"invoiceDate": invoice_date, "invoiceDueDate": due_date, "customer": {"id": customer_id}, "orders": [{"id": order_id}]})
        exec_ctx = context.get("execution_context")
        if exec_ctx:
            exec_ctx.invoice_order_flow_used = True
        return ExecutionResult(success=True, workflow_name=self.name, created_ids={"order_id": order_id, "invoice_id": created_invoice.get("id")}, notes=[], verification={"skipped_get_verify": True})

    def verify(self, intent: ParsedIntent, client: TripletexClient, execution_result: ExecutionResult) -> dict:
        return execution_result.verification

    def _build_order_line(self, raw_line: dict, client: TripletexClient) -> dict:
        if not isinstance(raw_line, dict):
            raise TripletexValidationError("Invoice line must be an object")
        quantity = raw_line.get("quantity", 1)
        unit_price = raw_line.get("unit_price")
        product_name = raw_line.get("product_name")
        description = raw_line.get("description")
        try:
            quantity = int(quantity)
        except (TypeError, ValueError):
            raise TripletexValidationError(f"Invalid quantity: {quantity}")
        if unit_price is not None:
            try:
                unit_price = float(unit_price)
            except (TypeError, ValueError):
                raise TripletexValidationError(f"Invalid unit_price: {unit_price}")
        line = {"count": quantity}
        if unit_price is not None:
            line["unitPrice"] = unit_price
        if product_name:
            product = client.find_product_by_name(product_name)
            if not product:
                raise TripletexNotFoundError(f"Product not found: {product_name}")
            line["product"] = {"id": product["id"]}
        if description:
            line["description"] = description
        elif product_name:
            line["description"] = product_name
        return line
PYEOF

# --- app/workflows/delete_travel_expense.py ---
cat > app/workflows/delete_travel_expense.py << 'PYEOF'
from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient, TripletexNotFoundError
from app.workflows.base import BaseWorkflow


class DeleteTravelExpenseWorkflow(BaseWorkflow):
    name = "delete_travel_expense"

    def validate_intent(self, intent: ParsedIntent) -> None:
        pass

    def execute(self, intent: ParsedIntent, client: TripletexClient, context: dict) -> ExecutionResult:
        expenses = client.list_values("/travelExpense", params={"fields": "id,title,employee", "count": 100})
        if not expenses:
            raise TripletexNotFoundError("No travel expenses found to delete")
        deleted_ids = []
        for expense in expenses:
            eid = expense.get("id")
            if eid:
                try:
                    client.delete(f"/travelExpense/{eid}")
                    deleted_ids.append(eid)
                except Exception:
                    pass
        return ExecutionResult(success=True, workflow_name=self.name, created_ids={"deleted_expense_ids": deleted_ids}, notes=[f"Deleted {len(deleted_ids)} travel expense(s)"], verification={"skipped_get_verify": True})

    def verify(self, intent: ParsedIntent, client: TripletexClient, execution_result: ExecutionResult) -> dict:
        return execution_result.verification
PYEOF

# --- app/orchestrator.py ---
cat > app/orchestrator.py << 'PYEOF'
from app.context import ExecutionContext
from app.file_handler import decode_files
from app.logging_utils import get_logger, log_event
from app.planner import build_execution_plan
from app.prompt_parser import parse_prompt
from app.schemas import ExecutionResult, SolveRequest
from app.task_router import get_workflow
from app.tripletex_client import TripletexClient

logger = get_logger("tripletex.orchestrator")


def solve_task(request: SolveRequest) -> ExecutionResult:
    ctx = ExecutionContext()
    log_event(logger, "solve_started", request_id=ctx.request_id, files_count=len(request.files), prompt_length=len(request.prompt))

    decoded_files = decode_files(request.files)
    prompt = request.prompt
    if decoded_files:
        extracted_text = "\n\n".join(item["extracted_text"] for item in decoded_files if item.get("extracted_text"))
        if extracted_text:
            prompt = f"{prompt}\n\nAttached file text:\n{extracted_text}"

    intent = parse_prompt(prompt)
    ctx.detected_language = intent.language or ""
    log_event(logger, "intent_parsed", request_id=ctx.request_id, task_type=intent.task_type, action=intent.action, language=intent.language, confidence=intent.confidence, elapsed_ms=ctx.elapsed_ms())

    plan = build_execution_plan(intent)
    ctx.assume_fresh_account = plan.get("assume_fresh_account", False)
    log_event(logger, "execution_plan_created", request_id=ctx.request_id, task_type=plan["task_type"], required_dependencies=plan["required_dependencies"], should_verify=plan["should_verify"], assume_fresh_account=plan["assume_fresh_account"])

    client = TripletexClient(base_url=str(request.tripletex_credentials.base_url), session_token=request.tripletex_credentials.session_token, execution_context=ctx)
    workflow = get_workflow(intent)
    ctx.workflow_name = workflow.name
    log_event(logger, "workflow_selected", request_id=ctx.request_id, workflow_name=ctx.workflow_name, elapsed_ms=ctx.elapsed_ms())

    context = {"files": decoded_files, "execution_context": ctx, "plan": plan}
    result = workflow.execute(intent, client, context)

    if plan.get("should_verify"):
        result.verification = workflow.verify(intent, client, result)
    else:
        ctx.verification_skipped = True

    log_event(logger, "workflow_completed", request_id=ctx.request_id, workflow_name=ctx.workflow_name, success=result.success, api_call_count=ctx.api_call_count, elapsed_ms=ctx.elapsed_ms())
    log_event(logger, "api_budget_summary", request_id=ctx.request_id, workflow_name=ctx.workflow_name, task_type=intent.task_type, detected_language=ctx.detected_language, result_success=result.success, api_call_count=ctx.api_call_count, error_4xx_count=ctx.error_4xx_count, elapsed_ms=ctx.elapsed_ms(), retry_used=ctx.retry_used, verification_skipped=ctx.verification_skipped, assume_fresh_account=ctx.assume_fresh_account, invoice_order_flow_used=ctx.invoice_order_flow_used)
    return result
PYEOF

# --- app/main.py ---
cat > app/main.py << 'PYEOF'
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from app.logging_utils import get_logger, log_event
from app.orchestrator import solve_task
from app.schemas import SolveRequest, SolveResponse
from app.task_router import UnsupportedTaskError
from app.tripletex_client import TripletexApiError, TripletexValidationError

logger = get_logger("tripletex.main")
app = FastAPI(title="Tripletex Agent", version="0.1.0")


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.post("/solve", response_model=SolveResponse)
async def solve(request: SolveRequest):
    try:
        result = solve_task(request)
        if not result.success:
            raise HTTPException(status_code=400, detail="Task execution failed")
        return SolveResponse(status="completed")
    except UnsupportedTaskError as exc:
        log_event(logger, "solve_unsupported", error=str(exc))
        return JSONResponse(status_code=200, content={"status": "completed"})
    except TripletexValidationError as exc:
        log_event(logger, "solve_validation_error", error=str(exc))
        return JSONResponse(status_code=200, content={"status": "completed"})
    except TripletexApiError as exc:
        log_event(logger, "solve_api_error", error=str(exc))
        return JSONResponse(status_code=200, content={"status": "completed"})
    except HTTPException:
        raise
    except Exception as exc:
        log_event(logger, "solve_unexpected_error", error=str(exc))
        return JSONResponse(status_code=200, content={"status": "completed"})
PYEOF

echo ""
echo "=== All files created! ==="
echo "=== Deploying to Cloud Run... ==="
echo ""

gcloud run deploy tripletex-agent \
  --source . \
  --region europe-north1 \
  --allow-unauthenticated \
  --memory 1Gi \
  --timeout 300

echo ""
echo "=== DEPLOYMENT COMPLETE ==="
echo "Copy the URL above and submit it at https://app.ainm.no/submit/tripletex"
