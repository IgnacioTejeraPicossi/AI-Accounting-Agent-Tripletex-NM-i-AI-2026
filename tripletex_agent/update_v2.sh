#!/bin/bash
set -e
echo "=== Tripletex Agent v2 Update ==="
cd ~/tripletex_agent

echo ">>> Updating app/main.py"
cat > app/main.py << 'PYEOF'
import json
import sys
import traceback

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse


def log_json(event, **kwargs):
    try:
        msg = json.dumps({"event": event, **kwargs}, default=str, ensure_ascii=False)
        print(msg, file=sys.stdout, flush=True)
    except Exception:
        pass


app = FastAPI(title="Tripletex Agent", version="0.2.0")


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/solve")
@app.post("/")
async def solve(request: Request):
    try:
        body = await request.json()
    except Exception as e:
        log_json("json_parse_error", error=str(e))
        return JSONResponse({"status": "completed"})

    try:
        from app.orchestrator import solve_task
        solve_task(body)
    except Exception as e:
        log_json("solve_error", error=str(e), tb=traceback.format_exc()[-1500:])

    return JSONResponse({"status": "completed"})
PYEOF

echo ">>> Updating app/tripletex_client.py"
cat > app/tripletex_client.py << 'PYEOF'
"""Simplified Tripletex API client.

Matches the official example pattern exactly:
  requests.get(f"{base_url}/employee", auth=("0", session_token), params=...)

No Session object, no extra headers, just simple requests calls.
"""
import json
import sys

import requests


def log_json(event, **kwargs):
    try:
        msg = json.dumps({"event": event, **kwargs}, default=str, ensure_ascii=False)
        print(msg, file=sys.stdout, flush=True)
    except Exception:
        pass


class TripletexApiError(Exception):
    pass


class TripletexClient:
    def __init__(self, base_url, session_token):
        self.base_url = base_url.rstrip("/")
        self.token = session_token
        self.auth = ("0", session_token)

    def _url(self, path):
        if not path.startswith("/"):
            path = "/" + path
        return f"{self.base_url}{path}"

    def get(self, path, params=None):
        url = self._url(path)
        resp = requests.get(url, auth=self.auth, params=params, timeout=30)
        log_json("api", method="GET", url=url, status=resp.status_code)
        if resp.status_code >= 400:
            log_json("api_error", method="GET", url=url,
                     status=resp.status_code, body=resp.text[:500])
            raise TripletexApiError(
                f"GET {path} -> {resp.status_code}: {resp.text[:300]}")
        return self._parse(resp)

    def post(self, path, payload=None):
        url = self._url(path)
        resp = requests.post(url, auth=self.auth, json=payload, timeout=30)
        log_json("api", method="POST", url=url, status=resp.status_code)
        if resp.status_code >= 400:
            log_json("api_error", method="POST", url=url,
                     status=resp.status_code, body=resp.text[:500],
                     sent_payload=payload)
            raise TripletexApiError(
                f"POST {path} -> {resp.status_code}: {resp.text[:300]}")
        return self._parse(resp)

    def put(self, path, payload=None):
        url = self._url(path)
        resp = requests.put(url, auth=self.auth, json=payload, timeout=30)
        log_json("api", method="PUT", url=url, status=resp.status_code)
        if resp.status_code >= 400:
            raise TripletexApiError(
                f"PUT {path} -> {resp.status_code}: {resp.text[:300]}")
        return self._parse(resp)

    def delete(self, path):
        url = self._url(path)
        resp = requests.delete(url, auth=self.auth, timeout=30)
        log_json("api", method="DELETE", url=url, status=resp.status_code)
        if resp.status_code >= 400:
            raise TripletexApiError(
                f"DELETE {path} -> {resp.status_code}: {resp.text[:300]}")
        return None

    def _parse(self, resp):
        if not resp.content:
            return None
        try:
            data = resp.json()
        except ValueError:
            return None
        if isinstance(data, dict) and "value" in data:
            return data["value"]
        return data
PYEOF

echo ">>> Updating app/prompt_parser.py"
cat > app/prompt_parser.py << 'PYEOF'
"""Multilingual prompt parser for Tripletex competition tasks.

Supports 7 languages: nb, nn, en, es, pt, de, fr.
Returns plain dicts (no Pydantic models) for maximum robustness.
"""
import re

UC = r'A-Z\u00c0-\u00d6\u00d8-\u00de'
LC = r'a-z\u00e0-\u00f6\u00f8-\u00ff'

EMAIL_RE = re.compile(r'[\w.\-+]+@[\w.\-]+\.\w+')
DATE_RE = re.compile(r'\d{4}-\d{2}-\d{2}')
PHONE_KW_RE = re.compile(
    r'(?:telefon|phone|mobil|mobile|tlf|tel|mobilnummer|telefonnummer'
    r'|tel[e\u00e9]fono|t[e\u00e9]l[e\u00e9]phone|handynummer|celular)'
    r'\s*:?\s*(\+?\d[\d\s\-]{6,14}\d)', re.IGNORECASE)

LANGUAGE_HINTS = {
    "nb": ["opprett", "ansatt", "kunde", "faktura", "prosjekt",
           "reiseregning", "avdeling", "bestilling", "slett", "legg til",
           "endre", "med navn", "som heter", "skal v\u00e6re"],
    "nn": ["opprett", "tilsett", "kunde", "faktura", "prosjekt",
           "reiserekning", "som heiter"],
    "es": ["crear", "empleado", "cliente", "producto", "factura",
           "proyecto", "eliminar", "departamento", "llamado"],
    "en": ["create", "employee", "customer", "product", "invoice",
           "project", "delete", "department", "named"],
    "pt": ["criar", "funcion\u00e1rio", "cliente", "produto", "fatura",
           "projeto", "departamento", "chamado"],
    "de": ["erstellen", "mitarbeiter", "kunde", "produkt", "rechnung",
           "projekt", "abteilung", "l\u00f6schen", "namens"],
    "fr": ["cr\u00e9er", "employ\u00e9", "client", "produit", "facture",
           "projet", "d\u00e9partement", "supprimer", "nomm\u00e9"],
}

ENTITY_CHECKS = [
    ("travel_expense", [
        "travel expense", "reiseregning", "reisekostnad",
        "gasto de viaje", "despesa de viagem", "reisekosten",
        "frais de voyage", "travel report", "reiserekning"]),
    ("invoice", [
        "invoice", "faktura", "factura", "rechnung", "facture", "fatura"]),
    ("payment", [
        "payment", "betaling", "innbetaling", "pago", "pagamento",
        "zahlung", "paiement"]),
    ("department", [
        "department", "departamento", "avdeling", "abteilung",
        "d\u00e9partement"]),
    ("employee", [
        "employee", "ansatt", "empleado", "employ\u00e9", "mitarbeiter",
        "funcion\u00e1rio", "arbeidstaker", "tilsett"]),
    ("customer", [
        "customer", "kunde", "cliente", "client", "klient"]),
    ("product", [
        "product", "produkt", "producto", "produit", "produto", "vare"]),
    ("project", [
        "project", "prosjekt", "proyecto", "projekt", "projet", "projeto"]),
    ("order", [
        "order", "ordre", "bestilling", "pedido", "bestellung", "commande"]),
]

SKIP_NAME_WORDS = {
    "Create", "Crear", "Opprett", "Lag", "Criar", "Erstellen", "Cr\u00e9er",
    "Register", "Registrer", "Registrar", "Registrieren", "Enregistrer",
    "Delete", "Eliminar", "Slett", "Fjern", "Apagar", "L\u00f6schen",
    "Supprimer", "Remove",
    "Update", "Actualizar", "Oppdater", "Endre", "Atualizar",
    "Aktualisieren",
    "Employee", "Empleado", "Ansatt", "Mitarbeiter", "Employ\u00e9",
    "Funcion\u00e1rio", "Tilsett", "Arbeidstaker",
    "Customer", "Cliente", "Kunde", "Client", "Klient",
    "Product", "Producto", "Produkt", "Produit", "Produto", "Vare",
    "Project", "Proyecto", "Prosjekt", "Projekt", "Projet",
    "Invoice", "Factura", "Faktura", "Rechnung", "Facture",
    "Department", "Departamento", "Avdeling", "Abteilung",
    "Travel", "Reise", "Viaje", "Voyage",
    "She", "He", "The", "This", "That", "An", "Ein", "Eine", "Un", "Una",
    "En", "Et", "Les", "Des", "Die", "Der", "Das",
    "Han", "Hun", "Med", "Til", "For", "Som", "Og", "Skal",
    "V\u00e6re", "Bli", "Den", "Det", "Hos",
    "With", "And", "Named", "Called", "Should", "Must", "Will", "Not",
    "But", "From", "Into",
    "Kontoadministrator", "Administrator", "Administrador",
    "Email", "Epost", "Telefon", "Phone", "Mobile", "Mobil",
    "Navn", "Name", "Nombre", "Nom", "Nome",
    "Legg", "Add", "Set", "Sett",
    "Nuevo", "Nouvelle", "Nuevo", "Neuer", "Neue", "Ny", "Nytt",
}


def detect_language(text):
    lower = text.lower()
    scores = {
        lang: sum(1 for w in hints if w in lower)
        for lang, hints in LANGUAGE_HINTS.items()
    }
    best = max(scores, key=scores.get, default="en")
    return best if scores.get(best, 0) > 0 else "en"


def detect_action(text):
    lower = text.lower()
    for w in ["delete", "eliminar", "slett", "fjern", "apagar",
              "l\u00f6schen", "supprimer", "remove", "slette"]:
        if w in lower:
            return "delete"
    for w in ["update", "actualizar", "oppdater", "endre", "atualizar",
              "aktualisieren", "mettre \u00e0 jour", "change", "cambiar"]:
        if w in lower:
            return "update"
    return "create"


def detect_entity(text):
    lower = text.lower()
    for entity, keywords in ENTITY_CHECKS:
        for kw in keywords:
            if kw in lower:
                return entity
    return "unknown"


def extract_person_name(text):
    """Extract (first_name, last_name) from an employee prompt."""
    pat = (
        rf'(?:med\s+navn|named?|llamado|nomm\u00e9e?|chamado|namens'
        rf'|som\s+heter|som\s+heiter|navn)\s+'
        rf'([{UC}][{LC}\'\-]+)\s+'
        rf'([{UC}][{LC}\'\-]+(?:\s+[{UC}][{LC}\'\-]+)*)'
    )
    m = re.search(pat, text)
    if m:
        return m.group(1), m.group(2)

    tokens = re.findall(rf'[{UC}][{LC}\'\-]+', text)
    consecutive = []
    for token in tokens:
        if token not in SKIP_NAME_WORDS:
            consecutive.append(token)
        else:
            if len(consecutive) >= 2:
                break
            consecutive = []

    if len(consecutive) >= 2:
        return consecutive[0], " ".join(consecutive[1:])

    filtered = [t for t in tokens if t not in SKIP_NAME_WORDS]
    if len(filtered) >= 2:
        return filtered[0], filtered[1]
    if len(filtered) == 1:
        return filtered[0], ""
    return "Unknown", "Unknown"


def extract_entity_name(text, entity_type=None):
    """Extract name for customer / product / project / department."""
    for pat in [r'"([^"]+)"', r"'([^']+)'"]:
        m = re.search(pat, text)
        if m:
            return m.group(1).strip()

    named_pat = (
        r'(?:med\s+navn|named?|called|kalt|som\s+heter|som\s+heiter'
        r'|nomm\u00e9e?|llamado|chamado|namens)\s+'
        r'(.+?)'
        r'(?:\s*[,\.]'
        r'|\s+(?:with|con|med|mit|avec|for|para|f\u00fcr|pour'
        r'|og|and|y|e|et|und|som|der|qui|que|that)\s'
        r'|$)'
    )
    m = re.search(named_pat, text, re.IGNORECASE)
    if m:
        name = m.group(1).strip()
        name = re.sub(
            r'\s+(?:with|con|med|mit|avec|for|para|f\u00fcr|pour'
            r'|og|and|y|e|et|und)\s*$', '', name, flags=re.IGNORECASE)
        if name:
            return name

    suffix_pat = (
        rf'([{UC}][{UC}{LC}\w\s&.\-]*?)'
        r'\s+(AS|AB|GmbH|Ltd|Inc|SA|SL|Corp|AG|ApS|Oy|NV|BV)\b'
    )
    m = re.search(suffix_pat, text)
    if m:
        return f"{m.group(1).strip()} {m.group(2)}"

    return None


def extract_customer_name_for_invoice(text):
    """Aggressively extract customer name from invoice/project prompts."""

    # "til kunde/kunden NAME"
    m = re.search(
        rf'(?:til\s+)?(?:kunde(?:n)?|klient(?:en)?)\s+'
        rf'([{UC}][{UC}{LC}\w\s&.\-]+?)'
        rf'(?:\s*[,\.]|\s+(?:for|med|with|con|mit|avec|og|and|som)\s|$)',
        text, re.IGNORECASE)
    if m:
        return m.group(1).strip()

    # "faktura/invoice til/for NAME" (key Norwegian pattern)
    m = re.search(
        rf'(?:faktura|fatura|invoice|factura|rechnung|facture)\s+'
        rf'(?:til|para|for|f\u00fcr|pour|to|a)\s+'
        rf'(?:(?:the|den|el|le|der|die|das)\s+)?'
        rf'(?:customer|client|kunde|kunden|cliente|klient)?\s*'
        rf'([{UC}][{UC}{LC}\w\s&.\-]+?)'
        rf'(?:\s*[,\.]|\s+(?:for|med|with|con|mit|avec|og|and|som|der'
        rf'|qui|que|containing|inkludert)\s|$)',
        text, re.IGNORECASE)
    if m:
        name = m.group(1).strip()
        name = re.sub(
            r'\s+(?:for|med|with|con|mit|avec|og|and|som)\s*$',
            '', name, flags=re.IGNORECASE)
        if name:
            return name

    # "for customer NAME" / "pour le client NAME" / etc.
    m = re.search(
        rf'(?:for\s+(?:the\s+)?(?:customer|client)'
        rf'|para\s+(?:el\s+)?cliente'
        rf'|for\s+kunden?'
        rf'|f\u00fcr\s+(?:den\s+)?kunden'
        rf'|pour\s+(?:le\s+)?client)\s+'
        rf'([{UC}][{UC}{LC}\w\s&.\-]+?)'
        rf'(?:\s*[,\.]|\s+(?:with|con|med|mit|avec|for|para|f\u00fcr'
        rf'|pour|og|and)\s|$)',
        text, re.IGNORECASE)
    if m:
        return m.group(1).strip()

    # Company suffix anywhere (NAME AS, NAME GmbH, etc.)
    m = re.search(
        rf'([{UC}][{UC}{LC}\w\s&.\-]*?)'
        r'\s+(AS|AB|GmbH|Ltd|Inc|SA|SL|Corp|AG)\b',
        text)
    if m:
        return f"{m.group(1).strip()} {m.group(2)}"

    # After "til/to/for" + capitalized multi-word name
    m = re.search(
        rf'(?:til|to|para|pour|f\u00fcr|for|a)\s+'
        rf'([{UC}][{LC}]+(?:\s+[{UC}][{LC}]+)+)',
        text)
    if m:
        candidate = m.group(1).strip()
        first_word = candidate.split()[0]
        if first_word not in {"Med", "For", "Og", "Som", "Til", "Den", "Det",
                              "The", "With", "And"}:
            return candidate

    return None


def extract_invoice_lines(text):
    """Extract line items from invoice prompts."""
    lines = []

    # "N stykk/timer/units PRODUCT til/at PRICE kr"
    m = re.search(
        rf'(\d+)\s+'
        rf'(?:stykk?|stk|units?|pcs|unit\u00e9s?|unidades?|st\u00fcck'
        rf'|timer?|hours?|horas?|Stunden?)\s+'
        rf'([{UC}{LC}][\w\s]*?)'
        rf'(?:\s+(?:til|at|\u00e0|a|zu|por|for)\s+'
        rf'(\d[\d\s]*[,.]?\d*)\s*(?:kr|NOK|EUR|USD|per|pr)?)?',
        text, re.IGNORECASE)
    if m:
        line = {
            "quantity": int(m.group(1)),
            "product_name": m.group(2).strip(),
        }
        if m.group(3):
            price_str = m.group(3).replace(" ", "").replace(",", ".")
            try:
                line["unit_price"] = float(price_str)
            except ValueError:
                pass
        lines.append(line)
        return lines

    # "N x PRICE"
    m = re.search(
        r'(\d+)\s*[x\u00d7]\s*(\d[\d\s]*[,.]?\d*)\s*(?:kr|NOK|EUR|USD)?',
        text, re.IGNORECASE)
    if m:
        lines.append({
            "quantity": int(m.group(1)),
            "unit_price": float(m.group(2).replace(" ", "").replace(",", ".")),
            "product_name": "Product",
        })
        return lines

    # Explicit quantity/price keywords
    qty = re.search(
        r'(?:antall|quantity|cantidad|quantit\u00e9|anzahl|mengde|antal)'
        r'\s*:?\s*(\d+)', text, re.IGNORECASE)
    price = re.search(
        r'(?:pris|price|precio|prix|preis|pre\u00e7o|kostnad)'
        r'\s*:?\s*(\d[\d\s]*[,.]?\d*)', text, re.IGNORECASE)

    if qty or price:
        line = {"product_name": "Konsulentarbeid"}
        line["quantity"] = int(qty.group(1)) if qty else 1
        if price:
            p = price.group(1).replace(" ", "").replace(",", ".")
            try:
                line["unit_price"] = float(p)
            except ValueError:
                pass
        lines.append(line)
        return lines

    return lines


def parse_prompt(prompt):
    """Parse a task prompt into a plain dict."""
    text = prompt.strip()
    language = detect_language(text)
    action = detect_action(text)
    entity = detect_entity(text)

    fields = {}
    email_m = EMAIL_RE.search(text)
    if email_m:
        fields["email"] = email_m.group(0)

    phone_m = PHONE_KW_RE.search(text)
    if phone_m:
        fields["phone"] = phone_m.group(1).strip()

    dates = DATE_RE.findall(text)
    if dates:
        fields["dates"] = dates

    task_type = "unsupported"
    entities = {}

    if entity == "employee":
        task_type = f"{action}_employee"
        first_name, last_name = extract_person_name(text)
        entities["employee"] = {
            "first_name": first_name, "last_name": last_name}

    elif entity == "customer":
        task_type = f"{action}_customer"
        name = extract_entity_name(text, "customer")
        entities["customer"] = {"name": name or "Unknown"}

    elif entity == "product":
        task_type = f"{action}_product"
        name = extract_entity_name(text, "product")
        entities["product"] = {"name": name or "Unknown"}

    elif entity == "project":
        task_type = f"{action}_project"
        name = extract_entity_name(text, "project")
        customer_name = extract_customer_name_for_invoice(text)
        entities["project"] = {"name": name or "Unknown"}
        if customer_name:
            fields["customer_name"] = customer_name
        if dates:
            fields["start_date"] = dates[0]
            if len(dates) >= 2:
                fields["end_date"] = dates[1]

    elif entity == "invoice":
        task_type = f"{action}_invoice"
        customer_name = extract_customer_name_for_invoice(text)
        invoice_lines = extract_invoice_lines(text)
        entities["invoice"] = {
            "customer_name": customer_name,
            "lines": invoice_lines,
            "invoice_date": dates[0] if dates else None,
            "due_date": dates[1] if len(dates) >= 2 else None,
        }
        fields["customer_name"] = customer_name

    elif entity == "travel_expense":
        task_type = f"{action}_travel_expense"

    elif entity == "department":
        task_type = f"{action}_department"
        name = extract_entity_name(text, "department")
        entities["department"] = {"name": name or "Unknown"}

    elif entity == "payment":
        task_type = "register_payment"

    elif entity == "order":
        task_type = f"{action}_order"

    return {
        "task_type": task_type,
        "action": action,
        "language": language,
        "entities": entities,
        "fields": fields,
        "raw_prompt": text,
    }
PYEOF

echo ">>> Updating app/orchestrator.py"
cat > app/orchestrator.py << 'PYEOF'
"""Orchestrator v2 - simplified with inline workflow handlers.

Key changes from v1:
- Accepts raw dict (no Pydantic model)
- Logs full prompt text for debugging
- Creates prerequisites instead of searching (fresh account per submission)
- All workflow logic is inline (no separate workflow classes needed)
"""
import json
import sys
import time
import traceback
from datetime import date


def log_json(event, **kwargs):
    try:
        msg = json.dumps(
            {"event": event, **kwargs}, default=str, ensure_ascii=False)
        print(msg, file=sys.stdout, flush=True)
    except Exception:
        pass


def solve_task(body):
    start = time.time()

    prompt = body.get("prompt", "")
    files = body.get("files") or []
    creds = body.get("tripletex_credentials") or {}
    base_url = str(creds.get("base_url", "")).strip()
    session_token = str(creds.get("session_token", "")).strip()

    log_json("solve_started",
             prompt=prompt,
             base_url=base_url,
             token_length=len(session_token),
             files_count=len(files))

    if not base_url or not session_token:
        log_json("missing_credentials")
        return

    from app.prompt_parser import parse_prompt
    intent = parse_prompt(prompt)

    safe_fields = {
        k: v for k, v in intent.get("fields", {}).items()
        if k != "raw_prompt"
    }
    log_json("intent_parsed",
             task_type=intent["task_type"],
             action=intent["action"],
             language=intent["language"],
             entities=intent.get("entities", {}),
             fields=safe_fields)

    from app.tripletex_client import TripletexClient
    client = TripletexClient(base_url, session_token)

    task_type = intent["task_type"]

    try:
        handler = _HANDLERS.get(task_type)
        if handler:
            handler(intent, client)
        else:
            log_json("unsupported_task", task_type=task_type)
    except Exception as e:
        log_json("workflow_error",
                 task_type=task_type,
                 error=str(e),
                 tb=traceback.format_exc()[-1000:])

    elapsed = int((time.time() - start) * 1000)
    log_json("solve_completed", task_type=task_type, elapsed_ms=elapsed)


# ---------------------------------------------------------------------------
# Workflow handlers
# ---------------------------------------------------------------------------

def _handle_create_employee(intent, client):
    emp = intent.get("entities", {}).get("employee", {})
    fields = intent.get("fields", {})

    payload = {
        "firstName": emp.get("first_name", "Unknown"),
        "lastName": emp.get("last_name", "Unknown"),
    }
    if fields.get("email"):
        payload["email"] = fields["email"]
    if fields.get("phone"):
        payload["mobileNumber"] = fields["phone"]

    result = client.post("/employee", payload)
    eid = result.get("id") if isinstance(result, dict) else None
    log_json("employee_created", id=eid)


def _handle_create_customer(intent, client):
    cust = intent.get("entities", {}).get("customer", {})
    fields = intent.get("fields", {})

    payload = {"name": cust.get("name", "Unknown"), "isCustomer": True}
    if fields.get("email"):
        payload["email"] = fields["email"]

    result = client.post("/customer", payload)
    cid = result.get("id") if isinstance(result, dict) else None
    log_json("customer_created", id=cid)


def _handle_create_product(intent, client):
    prod = intent.get("entities", {}).get("product", {})

    payload = {"name": prod.get("name", "Unknown")}

    result = client.post("/product", payload)
    pid = result.get("id") if isinstance(result, dict) else None
    log_json("product_created", id=pid)


def _handle_create_project(intent, client):
    proj = intent.get("entities", {}).get("project", {})
    fields = intent.get("fields", {})

    payload = {"name": proj.get("name", "Unknown")}

    customer_name = fields.get("customer_name")
    if customer_name:
        cust = client.post(
            "/customer", {"name": customer_name, "isCustomer": True})
        cid = cust.get("id") if isinstance(cust, dict) else None
        if cid:
            payload["customer"] = {"id": cid}

    if fields.get("description"):
        payload["description"] = fields["description"]
    if fields.get("start_date"):
        payload["startDate"] = fields["start_date"]
    if fields.get("end_date"):
        payload["endDate"] = fields["end_date"]

    result = client.post("/project", payload)
    pid = result.get("id") if isinstance(result, dict) else None
    log_json("project_created", id=pid)


def _handle_create_invoice(intent, client):
    invoice = intent.get("entities", {}).get("invoice", {})
    fields = intent.get("fields", {})

    customer_name = (
        invoice.get("customer_name") or fields.get("customer_name"))
    raw_lines = invoice.get("lines") or []
    invoice_date = invoice.get("invoice_date") or str(date.today())
    due_date = invoice.get("due_date") or invoice_date

    if not customer_name:
        log_json("invoice_no_customer",
                 prompt=intent.get("raw_prompt", "")[:500])
        return

    # Step 1 - create customer (fresh account)
    cust = client.post(
        "/customer", {"name": customer_name, "isCustomer": True})
    customer_id = cust.get("id") if isinstance(cust, dict) else None
    if not customer_id:
        log_json("invoice_customer_failed", response=str(cust)[:300])
        return

    # Step 2 - build order lines (create products)
    order_lines = []
    for raw_line in raw_lines:
        ol = _build_order_line(raw_line, client)
        if ol:
            order_lines.append(ol)

    if not order_lines:
        prod = client.post("/product", {"name": "Konsulentarbeid"})
        pid = prod.get("id") if isinstance(prod, dict) else None
        if pid:
            order_lines.append({
                "product": {"id": pid},
                "count": 1,
                "unitPriceExcludingVatCurrency": 100.0,
                "description": "Konsulentarbeid",
            })

    if not order_lines:
        log_json("invoice_no_lines")
        return

    # Step 3 - create order
    order = client.post("/order", {
        "customer": {"id": customer_id},
        "orderLines": order_lines,
    })
    order_id = order.get("id") if isinstance(order, dict) else None
    if not order_id:
        log_json("invoice_order_failed", response=str(order)[:500])
        return

    # Step 4 - create invoice
    inv = client.post("/invoice", {
        "invoiceDate": invoice_date,
        "invoiceDueDate": due_date,
        "customer": {"id": customer_id},
        "orders": [{"id": order_id}],
    })
    inv_id = inv.get("id") if isinstance(inv, dict) else None
    log_json("invoice_created", id=inv_id, order_id=order_id)


def _build_order_line(raw_line, client):
    if not isinstance(raw_line, dict):
        return None

    quantity = raw_line.get("quantity", 1)
    unit_price = raw_line.get("unit_price", 100.0)
    product_name = raw_line.get("product_name", "Product")

    prod = client.post("/product", {"name": product_name})
    pid = prod.get("id") if isinstance(prod, dict) else None

    line = {"count": int(quantity), "description": product_name}
    if pid:
        line["product"] = {"id": pid}
    if unit_price:
        line["unitPriceExcludingVatCurrency"] = float(unit_price)
    return line


def _handle_delete_travel(intent, client):
    data = client.get(
        "/travelExpense", params={"fields": "id", "count": 100})

    expenses = []
    if isinstance(data, dict) and "values" in data:
        expenses = data["values"]
    elif isinstance(data, list):
        expenses = data

    deleted = 0
    for exp in expenses:
        eid = exp.get("id")
        if eid:
            try:
                client.delete(f"/travelExpense/{eid}")
                deleted += 1
            except Exception as e:
                log_json("delete_travel_fail", id=eid, error=str(e))

    log_json("travel_deleted", count=deleted)


def _handle_create_department(intent, client):
    dept = intent.get("entities", {}).get("department", {})
    name = dept.get("name", "Unknown")

    result = client.post("/department", {"name": name})
    did = result.get("id") if isinstance(result, dict) else None
    log_json("department_created", id=did)


_HANDLERS = {
    "create_employee": _handle_create_employee,
    "create_customer": _handle_create_customer,
    "create_product": _handle_create_product,
    "create_project": _handle_create_project,
    "create_invoice": _handle_create_invoice,
    "delete_travel_expense": _handle_delete_travel,
    "create_department": _handle_create_department,
}
PYEOF

echo "=== Files updated. Deploying to Cloud Run... ==="
gcloud run deploy tripletex-agent \
  --source . \
  --region europe-north1 \
  --allow-unauthenticated \
  --memory 1Gi \
  --timeout 300

echo "=== Done! ==="
