#!/usr/bin/env bash
set -euo pipefail

echo "=== v5: Invoice fix (orderDate/deliveryDate, multi-product lines, VAT types, org number) ==="

# --- prompt_parser.py ---
cat > ~/tripletex_agent/app/prompt_parser.py << 'PYEOF'
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
    r'|tel[eé]fono|t[eé]l[eé]phone|handynummer|celular)'
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
    """Find the entity whose keyword appears EARLIEST in the text."""
    lower = text.lower()
    best_entity = "unknown"
    best_pos = len(lower) + 1

    for entity, keywords in ENTITY_CHECKS:
        for kw in keywords:
            pos = lower.find(kw)
            if pos != -1 and pos < best_pos:
                best_pos = pos
                best_entity = entity

    return best_entity


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


def extract_all_quoted_names(text):
    """Extract ALL quoted names from text."""
    for pat in [r'"([^"]+)"', r'\u201c([^\u201d]+)\u201d',
                r"'([^']+)'", r'\u00ab([^\u00bb]+)\u00bb']:
        names = re.findall(pat, text)
        if names:
            return [n.strip() for n in names if n.strip()]
    return []


def extract_entity_name(text, entity_type=None):
    """Extract name for customer / product / project / department."""
    for pat in [r'"([^"]+)"', r"'([^']+)'",
                r'\u201c([^\u201d]+)\u201d', r'\u00ab([^\u00bb]+)\u00bb']:
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


def extract_org_number(text):
    """Extract organization number from text."""
    m = re.search(
        r'(?:org\.?\s*(?:n[°º]?|nr\.?|number|nummer|no\.?)\s*)(\d{6,12})',
        text, re.IGNORECASE)
    if m:
        return m.group(1)
    return None


def extract_project_manager(text, email=None):
    """Extract project manager/director from text."""
    if email:
        pat = (
            rf'([{UC}][{LC}\'\-]+(?:\s+[{UC}][{LC}\'\-]+)+)'
            rf'\s*\({re.escape(email)}\)'
        )
        m = re.search(pat, text)
        if m:
            parts = m.group(1).strip().split()
            if len(parts) >= 2:
                return {
                    "first_name": parts[0],
                    "last_name": " ".join(parts[1:]),
                    "email": email,
                }

    patterns = [
        rf'(?:(?:el\s+)?director(?:a)?|(?:the\s+)?(?:project\s+)?manager'
        rf'|prosjektleder|projektleder|(?:le\s+)?directeur(?:rice)?'
        rf'|(?:der\s+)?(?:Projekt)?leiter(?:in)?|(?:el\s+)?jefe|gerente)'
        rf'(?:\s+(?:del\s+proyecto|of\s+(?:the\s+)?project|du\s+projet'
        rf'|des\s+Projekts|av\s+prosjektet))?\s+'
        rf'(?:es|is|er|est|ist)\s+'
        rf'([{UC}][{LC}\'\-]+(?:\s+[{UC}][{LC}\'\-]+)+)',
    ]
    for pat in patterns:
        m = re.search(pat, text, re.IGNORECASE)
        if m:
            parts = m.group(1).strip().split()
            if len(parts) >= 2:
                return {
                    "first_name": parts[0],
                    "last_name": " ".join(parts[1:]),
                    "email": email,
                }
    return None


def extract_customer_name_for_invoice(text):
    """Aggressively extract customer name from invoice/project prompts."""

    m = re.search(
        rf'(?:(?:til|al|del|ao|du|zum|au|to)\s+)?'
        rf'(?:kunde(?:n)?|klient(?:en)?|cliente|customer|client)\s+'
        rf'([{UC}][{UC}{LC}\w\s&.\-]+?)'
        rf'(?:\s*[\(,\.]|\s+(?:for|med|with|con|mit|avec|og|and|som'
        rf'|vinculado|linked|que|y|und|et)\s|$)',
        text, re.IGNORECASE)
    if m:
        return m.group(1).strip()

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

    m = re.search(
        rf'([{UC}][{UC}{LC}\w\s&.\-]*?)'
        r'\s+(AS|AB|GmbH|Ltd|Inc|SA|SL|Corp|AG)\b',
        text)
    if m:
        return f"{m.group(1).strip()} {m.group(2)}"

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

    # Pattern 1: "ProductName (ProductNumber) til Price kr med VAT% MVA"
    multi = re.findall(
        r'([\w]+(?:\s+[\w]+)*?)\s*\((\d{3,})\)\s*'
        r'(?:til|at|\u00e0|a|zu|por|for)\s+'
        r'(\d[\d\s]*)\s*(?:kr|NOK|EUR|USD)\s*'
        r'(?:med|with|con|mit|avec|com)\s+(\d+)\s*%',
        text, re.IGNORECASE | re.UNICODE)
    if multi:
        for name, number, price_str, vat_str in multi:
            clean_name = re.sub(
                r'^(?:og|and|y|e|et|und|,)\s+', '', name.strip(),
                flags=re.IGNORECASE).strip()
            price = float(price_str.replace(" ", "").replace(",", "."))
            lines.append({
                "product_name": clean_name,
                "product_number": number,
                "unit_price": price,
                "vat_rate": int(vat_str),
                "quantity": 1,
            })
        return lines

    # Pattern 2: "N stykk/timer/units PRODUCT til/at PRICE kr"
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

    # Pattern 3: "N x PRICE"
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

    # Pattern 4: Explicit quantity/price keywords
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
        all_names = extract_all_quoted_names(text)
        if len(all_names) > 1:
            items = []
            for qn in all_names:
                parts = qn.split()
                if len(parts) >= 2:
                    items.append({"first_name": parts[0],
                                  "last_name": " ".join(parts[1:])})
                else:
                    items.append({"first_name": qn, "last_name": ""})
            entities["items"] = items
        else:
            first_name, last_name = extract_person_name(text)
            entities["employee"] = {
                "first_name": first_name, "last_name": last_name}

    elif entity == "customer":
        task_type = f"{action}_customer"
        all_names = extract_all_quoted_names(text)
        if len(all_names) > 1:
            entities["items"] = [{"name": n} for n in all_names]
        else:
            name = extract_entity_name(text, "customer")
            entities["customer"] = {"name": name or "Unknown"}

    elif entity == "product":
        task_type = f"{action}_product"
        all_names = extract_all_quoted_names(text)
        if len(all_names) > 1:
            entities["items"] = [{"name": n} for n in all_names]
        else:
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
        org_num = extract_org_number(text)
        if org_num:
            fields["org_number"] = org_num
        manager = extract_project_manager(text, fields.get("email"))
        if manager:
            fields["manager_first_name"] = manager["first_name"]
            fields["manager_last_name"] = manager["last_name"]
            fields["manager_email"] = manager.get("email")

    elif entity == "invoice":
        task_type = f"{action}_invoice"
        customer_name = extract_customer_name_for_invoice(text)
        invoice_lines = extract_invoice_lines(text)
        org_num = extract_org_number(text)
        entities["invoice"] = {
            "customer_name": customer_name,
            "lines": invoice_lines,
            "invoice_date": dates[0] if dates else None,
            "due_date": dates[1] if len(dates) >= 2 else None,
        }
        fields["customer_name"] = customer_name
        if org_num:
            fields["org_number"] = org_num

    elif entity == "travel_expense":
        task_type = f"{action}_travel_expense"

    elif entity == "department":
        task_type = f"{action}_department"
        all_names = extract_all_quoted_names(text)
        if len(all_names) > 1:
            entities["items"] = [{"name": n} for n in all_names]
        else:
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

echo "  [OK] prompt_parser.py updated"

# --- orchestrator.py ---
cat > ~/tripletex_agent/app/orchestrator.py << 'PYEOF'
"""Orchestrator v5 - invoice fix + multi-entity support.

Key changes:
- Order POST includes orderDate and deliveryDate (fixes 422)
- Invoice lines parsed from "ProductName (Number) til Price kr med VAT% MVA"
- VAT type lookup and assignment on products and order lines
- Customer org number passed on invoice creation
- All handlers support entities["items"] for batch creation
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
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})

    items = entities.get("items", [])
    if items:
        for item in items:
            payload = {
                "firstName": item.get("first_name", "Unknown"),
                "lastName": item.get("last_name", "Unknown"),
            }
            result = client.post("/employee", payload)
            eid = result.get("id") if isinstance(result, dict) else None
            log_json("employee_created", id=eid,
                     name=f"{item.get('first_name')} {item.get('last_name')}")
        return

    emp = entities.get("employee", {})
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
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})

    items = entities.get("items", [])
    if items:
        for item in items:
            payload = {"name": item.get("name", "Unknown"), "isCustomer": True}
            result = client.post("/customer", payload)
            cid = result.get("id") if isinstance(result, dict) else None
            log_json("customer_created", id=cid, name=item.get("name"))
        return

    cust = entities.get("customer", {})
    payload = {"name": cust.get("name", "Unknown"), "isCustomer": True}
    if fields.get("email"):
        payload["email"] = fields["email"]

    result = client.post("/customer", payload)
    cid = result.get("id") if isinstance(result, dict) else None
    log_json("customer_created", id=cid)


def _handle_create_product(intent, client):
    entities = intent.get("entities", {})

    items = entities.get("items", [])
    if items:
        for item in items:
            payload = {"name": item.get("name", "Unknown")}
            result = client.post("/product", payload)
            pid = result.get("id") if isinstance(result, dict) else None
            log_json("product_created", id=pid, name=item.get("name"))
        return

    prod = entities.get("product", {})
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
        cust_payload = {"name": customer_name, "isCustomer": True}
        org_num = fields.get("org_number")
        if org_num:
            cust_payload["organizationNumber"] = org_num
        cust = client.post("/customer", cust_payload)
        cid = cust.get("id") if isinstance(cust, dict) else None
        if cid:
            payload["customer"] = {"id": cid}

    mgr_first = fields.get("manager_first_name")
    mgr_last = fields.get("manager_last_name")
    if mgr_first and mgr_last:
        emp_payload = {"firstName": mgr_first, "lastName": mgr_last}
        mgr_email = fields.get("manager_email")
        if mgr_email:
            emp_payload["email"] = mgr_email
        emp = client.post("/employee", emp_payload)
        eid = emp.get("id") if isinstance(emp, dict) else None
        if eid:
            payload["projectManager"] = {"id": eid}

    if fields.get("description"):
        payload["description"] = fields["description"]
    if fields.get("start_date"):
        payload["startDate"] = fields["start_date"]
    if fields.get("end_date"):
        payload["endDate"] = fields["end_date"]

    result = client.post("/project", payload)
    pid = result.get("id") if isinstance(result, dict) else None
    log_json("project_created", id=pid)


def _get_vat_types(client):
    """Fetch available VAT types, return dict mapping percentage -> id."""
    vat_map = {}
    try:
        data = client.get("/ledger/vatType", params={"count": 100})
        items = []
        if isinstance(data, dict) and "values" in data:
            items = data["values"]
        elif isinstance(data, list):
            items = data
        for item in items:
            pct = item.get("percentage")
            vid = item.get("id")
            if pct is not None and vid is not None:
                pct_int = int(float(pct))
                if pct_int not in vat_map:
                    vat_map[pct_int] = vid
        log_json("vat_types_loaded", count=len(vat_map),
                 rates=list(vat_map.keys()))
    except Exception as e:
        log_json("vat_lookup_skipped", error=str(e)[:200])
    return vat_map


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

    cust_payload = {"name": customer_name, "isCustomer": True}
    org_num = fields.get("org_number")
    if org_num:
        cust_payload["organizationNumber"] = org_num

    cust = client.post("/customer", cust_payload)
    customer_id = cust.get("id") if isinstance(cust, dict) else None
    if not customer_id:
        log_json("invoice_customer_failed", response=str(cust)[:300])
        return

    vat_map = _get_vat_types(client)

    order_lines = []
    for raw_line in raw_lines:
        ol = _build_order_line(raw_line, client, vat_map)
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

    today = str(date.today())
    order = client.post("/order", {
        "customer": {"id": customer_id},
        "orderDate": invoice_date or today,
        "deliveryDate": invoice_date or today,
        "orderLines": order_lines,
    })
    order_id = order.get("id") if isinstance(order, dict) else None
    if not order_id:
        log_json("invoice_order_failed", response=str(order)[:500])
        return

    inv = client.post("/invoice", {
        "invoiceDate": invoice_date,
        "invoiceDueDate": due_date,
        "customer": {"id": customer_id},
        "orders": [{"id": order_id}],
    })
    inv_id = inv.get("id") if isinstance(inv, dict) else None
    log_json("invoice_created", id=inv_id, order_id=order_id)


def _build_order_line(raw_line, client, vat_map=None):
    if not isinstance(raw_line, dict):
        return None

    quantity = raw_line.get("quantity", 1)
    unit_price = raw_line.get("unit_price", 100.0)
    product_name = raw_line.get("product_name", "Product")
    product_number = raw_line.get("product_number")
    vat_rate = raw_line.get("vat_rate")

    prod_payload = {"name": product_name}
    if product_number:
        prod_payload["number"] = int(product_number)
    if vat_rate is not None and vat_map:
        vat_id = vat_map.get(vat_rate)
        if vat_id:
            prod_payload["vatType"] = {"id": vat_id}

    prod = client.post("/product", prod_payload)
    pid = prod.get("id") if isinstance(prod, dict) else None

    line = {"count": int(quantity), "description": product_name}
    if pid:
        line["product"] = {"id": pid}
    if unit_price:
        line["unitPriceExcludingVatCurrency"] = float(unit_price)
    if vat_rate is not None and vat_map:
        vat_id = vat_map.get(vat_rate)
        if vat_id:
            line["vatType"] = {"id": vat_id}
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
    entities = intent.get("entities", {})

    items = entities.get("items", [])
    if items:
        for item in items:
            name = item.get("name", "Unknown")
            result = client.post("/department", {"name": name})
            did = result.get("id") if isinstance(result, dict) else None
            log_json("department_created", id=did, name=name)
        return

    dept = entities.get("department", {})
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

echo "  [OK] orchestrator.py updated"

# --- Deploy ---
echo "=== Deploying v5 to Cloud Run ==="
cd ~/tripletex_agent
gcloud run deploy tripletex-agent \
  --source . \
  --region europe-north1 \
  --allow-unauthenticated \
  --memory 1Gi \
  --timeout 300

echo "=== Done! ==="
