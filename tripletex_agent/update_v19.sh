#!/usr/bin/env bash
set -euo pipefail

echo "=== v19: deploy bundle (prompt_parser + orchestrator) ==="

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
    ("supplier", [
        "leverand\u00f8r", "supplier", "vendor", "lieferant",
        "fournisseur", "proveedor", "fornecedor"]),
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

CREDIT_NOTE_KEYWORDS = [
    "credit note", "kreditnota", "kreditnotis", "nota de cr\u00e9dito",
    "gutschrift", "avoir", "nota di credito", "nota de cr\u00e9dito",
]

SUPPLIER_INVOICE_KEYWORDS = [
    "lieferantenrechnung", "leverand\u00f8rfaktura", "inng\u00e5ende faktura",
    "supplier invoice", "vendor invoice", "incoming invoice",
    "facture fournisseur", "factura de proveedor", "fatura de fornecedor",
]

PAYMENT_ACTION_KEYWORDS = [
    "enregistrez le paiement", "register the payment",
    "registrer betalingen", "registre o pagamento",
    "registrieren sie die zahlung", "registrar el pago",
    "paiement int\u00e9gral", "full payment", "full betaling",
    "facture impay\u00e9e", "unpaid invoice", "ubetalt faktura",
    "utestående faktura", "uteståande faktura", "fatura pendente",
    "factura pendiente", "offene rechnung",
    "reverse the payment", "tilbakef\u00f8r betaling",
    "returned by the bank", "returnert av banken",
    "devolvido pelo banco", "retourn\u00e9 par la banque",
    "montante em aberto", "montant impay\u00e9",
    "innbetaling", "enregistrez un paiement",
    "annulez le paiement", "pagamento total", "pagamento desta",
]

PAYMENT_ACTION_PATTERNS = [
    r'registr\w*\s+(?:\w+\s+)*betaling',
    r'regist\w*\s+(?:o\s+)?(?:\w+\s+)*pagamento',
    r'register\s+(?:\w+\s+)*payment',
    r'registr\w*\s+(?:\w+\s+)*pago',
    r'enregistr\w*\s+(?:\w+\s+)*paiement',
    r'registrier\w*\s+(?:\w+\s+)*zahlung',
]

SALARY_KEYWORDS = [
    "sal\u00e1rio", "l\u00f8nn", "salary", "salario", "salaire", "gehalt",
    "l\u00f8nnsslipp", "payslip", "n\u00f3mina", "bulletin de paie",
    "holerite", "payroll", "l\u00f8nnskj\u00f8ring",
    "processe o sal\u00e1rio", "process salary", "processar sal\u00e1rio",
    "processar o sal\u00e1rio", "processar salario",
]


def _salary_keyword_match(lower: str) -> bool:
    """Match salary keywords without false positives (e.g. lønn inside lønnsavsetjing)."""
    for sk in SALARY_KEYWORDS:
        if sk == "l\u00f8nn":
            if re.search(r"\bl\u00f8nn\b", lower):
                return True
        elif sk in lower:
            return True
    return False


def sanitize_supplier_name(name):
    """Reject instruction fragments mistaken for supplier names (PT/ES/EN)."""
    if not name:
        return None
    n = name.strip()
    low = n.lower()
    bad = (
        "se nao existir", "se não existir", "si no existe", "if not exist",
        "if it does not exist", "falls nicht", "sofern nicht",
        "creer le fournisseur", "crie o fornecedor", "cree el proveedor",
    )
    if low in bad or len(n) < 2:
        return None
    if re.match(
            r"(?i)^(se|si|if)\s+(nao|não|no)\s+exist",
            n):
        return None
    if re.match(r"(?i)^crie\s+o\s+fornecedor", n):
        return None
    return n

DIMENSION_KEYWORDS = [
    "rekneskapsdimensjon", "accounting dimension", "custom accounting dimension",
    "dimensi\u00f3n contable", "dimension comptable", "buchungsdimension",
    "dimensjonsverdi", "dimensjonsverdien", "produktlinje",
]

SUPPLIER_REGISTER_PATTERNS = [
    r"registrer\s+leverand",
    r"registrar\s+(?:el\s+)?proveedor",
    r"registre\s+le\s+fournisseur",
    r"lieferant(?:en)?\s+(?:anlegen|registrieren|erfassen)",
]

SKIP_NAME_WORDS = {
    "Create", "Crear", "Opprett", "Lag", "Criar", "Erstellen", "Cr\u00e9er",
    "Register", "Registrer", "Registrar", "Registrieren", "Enregistrer",
    "Erfassen", "Processe", "Processar", "Procesar",
    "Vous", "Creez", "Créez", "Tripletex",
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
    "Gjer", "Gj\u00f8r", "Bokf\u00f8r", "Bokfort", "Periodiser",
    "Kontroller", "Reconcilie",
    "Has", "Completa", "Effectuez", "Comptabilisez", "Enregistrez",
    "V\u00e9rifiez", "Verifiez",
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
    # Strip emails so faktura@firma.no does not match keyword "faktura"
    lower = EMAIL_RE.sub(" ", text).lower()

    # Month-end / ledger closing (must beat salary keyword "lønn" in lønnsavsetjing)
    if re.search(
            r"m\u00e5neds?avslutning|m\u00e5navslutning|periodiser|avskriving"
            r"|saldobalanse|l\u00f8nnsavsetjing|driftsmiddel|forskotsbetalt"
            r"|kontroller at|line\u00e6r avskriving|m\u00e5nadleg"
            r"|month[- ]end|closing entries|journal entries"
            r"|cl[oô]ture\s+mensuelle|effectuez la cl[oô]ture|comptabilisez"
            r"|r\u00e9gularisation|amortissement|balance est \u00e0 z\u00e9ro"
            r"|provision pour salaires|comptabilisez \u00e9galement",
            lower):
        return "ledger_closing"

    # FX / agio payment (not simple register_payment)
    if re.search(
            r"valutadiffer|valutadifferanse|agio|NOK/EUR|EUR.*NOK|kursen var"
            r"|differenza\s+cambi|diferencia\s+de\s+cambio",
            lower) and re.search(
            r"registrer\s+betaling|register\s+payment|bokf\u00f8r"
            r"|betalingen|pagamento",
            lower):
        return "ledger_fx_payment"

    # Reminder fee + AR + revenue + invoice + partial payment (multi-step)
    if re.search(
            r"recordatorio|cargo por recordatorio|cuentas por cobrar"
            r"|factura vencida|d\u00e9bito.*cr\u00e9dito|debito.*credito",
            lower) and re.search(
            r"1500|3400|pago parcial|partial payment",
            lower):
        return "payment_reminder_bundle"

    # Bank / statement reconciliation (not customer invoice creation)
    if re.search(
            r"reconcili|extrato\s+banc|bank\s+reconciliation|afstemming"
            r"|avstemm(?:ing)?|csv\s+anexo|bank\s+statement",
            lower):
        return "bank_reconciliation"

    # Analyze ledger + multiple internal projects / activities (not one create_project)
    if re.search(
            r"analyser hovudboka|finn dei tre|kostnadskontoane|st\u00f8rst auke"
            r"|internt prosjekt|kontoens namn|aktivitet for kvart prosjekt",
            lower):
        return "ledger_analysis"

    # Job offer / onboarding (beats "salario" in "salario anual")
    if re.search(
            r"carta de oferta|offer letter|job offer|contrat d\'embauche"
            r"|offertebrev|nuevo empleado|incorporaci[oó]n",
            lower) and re.search(
            r"empleado|employee|ansatt|crea(?:r)?\s+(?:el\s+)?empleado"
            r"|completa la incorpor",
            lower):
        return "employee"

    if _salary_keyword_match(lower):
        return "salary"

    if re.search(
            r"proces\w*\s+(?:o\s+)?(?:el\s+)?(?:sal[aá]rio|salario)"
            r"|(?:sal[aá]rio|salario|l\u00f8nn).{0,120}?proces",
            lower):
        return "salary"

    if re.search(
            r"contrat\s+de\s+travail|employment\s+contract|arbeidskontrakt"
            r"|contrato\s+de\s+trabajo",
            lower):
        return "salary"

    # Order→invoice→payment workflow (must win over keyword "paiement"/"payment")
    if re.search(
            r"(?:créez|créer|creez)\s+(?:une\s+)?(?:commande|order)"
            r"|(?:create|crear|crea)\s+(?:a\s+)?(?:an\s+)?(?:order|pedido|orden)"
            r"|bestill(?:ing)?\s+(?:og\s+)?(?:faktura|invoice)",
            lower):
        return "order"
    if re.search(
            r"(?:commande|order|bestilling|pedido)"
            r".{0,500}?(?:convert|facture|invoice|factura|faktura|fatura)"
            r".{0,400}?(?:paiement|payment|betaling|pago|pagamento|innbetaling)",
            lower, re.DOTALL):
        return "order"

    for pk in PAYMENT_ACTION_KEYWORDS:
        if pk in lower:
            return "payment"
    for pat in PAYMENT_ACTION_PATTERNS:
        if re.search(pat, lower):
            return "payment"

    for ck in CREDIT_NOTE_KEYWORDS:
        if ck in lower:
            return "credit_note"

    for sk in SUPPLIER_INVOICE_KEYWORDS:
        if sk in lower:
            return "supplier_invoice"

    if re.search(
            r'(?:rechnung|faktura|invoice|factura|fatura|facture)'
            r'.*(?:vom\s+lieferant|fra\s+leverand\u00f8r'
            r'|from\s+(?:the\s+)?(?:supplier|vendor)'
            r'|du\s+fournisseur|del\s+proveedor|do\s+fornecedor)',
            lower):
        return "supplier_invoice"

    for pat in SUPPLIER_REGISTER_PATTERNS:
        if re.search(pat, lower):
            return "supplier"

    for dk in DIMENSION_KEYWORDS:
        if dk in lower:
            return "dimension"

    if re.search(r"kvittering|togbillett|receipt", lower) and re.search(
            r"avdeling|department|administrasjon", lower, re.IGNORECASE):
        if re.search(
                r"bokf|bokf\u00f8|bokfort|book|posting|registrer|utgift",
                lower, re.IGNORECASE):
            return "expense_receipt"

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
    # Try: "Name Surname (email@...)" - most reliable
    email_m = EMAIL_RE.search(text)
    if email_m:
        before = text[:email_m.start()].rstrip().rstrip('(').rstrip()
        name_m = re.search(
            rf'([{UC}][{LC}\u00c0-\u024f\'\-]+)\s+'
            rf'([{UC}][{LC}\u00c0-\u024f\'\-]+(?:\s+[{UC}][{LC}\u00c0-\u024f\'\-]+)*)\s*$',
            before)
        if name_m:
            return name_m.group(1), name_m.group(2)

    pat = (
        rf'(?:med\s+navn|named?|llamado|nomm\u00e9e?|chamado|namens'
        rf'|som\s+heter|som\s+heiter|navn|f\u00fcr)\s+'
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

    em = re.search(
        r"(?:employ\u00e9|employe|employee|ansatt)\s+"
        r"([A-Z\u00c0-\u024f][a-z\u00e0-\u024f]+)\s+"
        r"([A-Z\u00c0-\u024f][a-z\u00e0-\u024f\-]+)",
        text, re.IGNORECASE)
    if em:
        return em.group(1), em.group(2)

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
        r'\s+(AS|AB|GmbH|Ltd|Lda|Ltda|Inc|SA|SL|SARL|Srl|Corp|AG|ApS|Oy|NV|BV)\b'
    )
    m = re.search(suffix_pat, text)
    if m:
        return f"{m.group(1).strip()} {m.group(2)}"

    return None


def extract_org_number(text):
    """Extract organization number from text."""
    m = re.search(
        r'(?:organis\w+nummer)\s*:?\s*(\d{6,12})',
        text, re.IGNORECASE)
    if m:
        return m.group(1)
    m = re.search(
        r'org\.?\s*[\-.]?\s*(?:n[°º]?\.?|nr\.?|number|nummer|no\.?)\s*:?\s*(\d{6,12})',
        text, re.IGNORECASE)
    if m:
        return m.group(1)
    m = re.search(
        r'n[°º]\.?\s*org\.?\s*:?\s*(\d{6,12})',
        text, re.IGNORECASE)
    if m:
        return m.group(1)
    m = re.search(
        r'n[uú]mero\s+de\s+organiza[çc][aã]o\s+(\d{6,12})',
        text, re.IGNORECASE)
    if m:
        return m.group(1)
    m = re.search(
        r'(?:Organisationsnummer|Organisasjonsnummer)\s+(\d{6,12})',
        text, re.IGNORECASE)
    if m:
        return m.group(1)
    m = re.search(r'\((?:org\.?\s*)?(\d{9})\)', text)
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

    # Spanish/Portuguese: "para Montaña SL (org. nº ...)" — high priority
    pm = re.search(
        r"para\s+([A-Za-zÁÉÍÓÚÑÜáéíóúñü0-9\s\.\-]+?)\s*\(\s*org",
        text, re.IGNORECASE)
    if pm:
        cand = re.sub(r"\s+", " ", pm.group(1).strip())
        if 3 < len(cand) < 120 and not re.match(
                r"(?i)^(la|el|los|las|una|un)\s", cand):
            return cand

    _TERM = (
        rf'(?:\s*[\(,\.]|\s+(?:for|med|with|con|com|mit|avec|og|and|som'
        rf'|vinculado|linked|que|y|und|et|n[uú]mero|referente)\s|$)'
    )

    # "pagamento/payment de/from NAME" (payment-specific)
    m = re.search(
        rf'(?:pagamento\s+de|payment\s+(?:from|of)'
        rf'|betaling\s+fra|paiement\s+de'
        rf'|zahlung\s+von|pago\s+de)\s+'
        rf'([{UC}][{UC}{LC}\w\s&.\-]+?)'
        + _TERM,
        text, re.IGNORECASE)
    if m:
        return m.group(1).strip()

    # Universal: optional preposition + customer keyword + NAME
    m = re.search(
        rf'(?:(?:til|al|del|ao|du|zum|au|to)\s+)?'
        rf'(?:kunde(?:n)?|klient(?:en)?|cliente|customer|client)\s+'
        rf'([{UC}][{UC}{LC}\w\s&.\-]+?)'
        + _TERM,
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

    m = re.search(
        rf'([{UC}][{UC}{LC}\w\s&.\-]*?)'
        r'\s+(AS|AB|GmbH|Ltd|Lda|Ltda|Inc|SA|SL|SARL|Srl|Corp|AG|ApS|Oy|NV|BV)\b',
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


def _bad_project_customer_name(name):
    """Phrases mistaken for company names in project prompts."""
    if not name:
        return True
    low = name.lower().strip()
    bad = (
        "basada en las horas", "basada", "horas registradas",
        "pour le projet", "y enví", "y envi", "al cliente basada",
        "factura de proyecto al cliente",
    )
    return any(b in low for b in bad)


def extract_project_customer_name(text):
    """Extract billable customer for project tasks (ES/FR); avoids 'para Lucía' as client."""
    # All "para Firma SL (org. nº ...)" — prefer legal suffix
    found = []
    for m in re.finditer(
            r"para\s+([A-Za-zÁÉÍÓÚÑÜáéíóúñü0-9\s\.\-]+?)\s*\(\s*org",
            text, re.IGNORECASE):
        cand = re.sub(r"\s+", " ", m.group(1).strip())
        if re.search(
                r"(?i)\b(SL|AS|SA|SARL|GmbH|Ltd|AB|Inc|Corp|LLC|ASA)\b",
                cand):
            return cand
        if len(cand) > 6:
            found.append(cand)
    if found:
        return found[-1]

    # French: "(Rivière SARL, nº org."
    fm = re.search(
        r"\(\s*([A-Za-zÀ-ÿ\-\s]+?(?:SARL|SL|AS|SA|Ltd|GmbH|AB))\s*,"
        r"\s*n[°º]?\s*org",
        text, re.IGNORECASE)
    if fm:
        return re.sub(r"\s+", " ", fm.group(1).strip()).strip()

    base = extract_customer_name_for_invoice(text)
    if base and not _bad_project_customer_name(base):
        return base
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


def parse_prompt(prompt, extra_text=None):
    """Parse a task prompt into a plain dict.

    extra_text: PDF or attachment text merged for classification (contracts, receipts).
    """
    text = prompt.strip()
    if extra_text:
        text = (text + "\n" + str(extra_text).strip()).strip()
    language = detect_language(text)
    action = detect_action(text)
    entity = detect_entity(text)

    if entity in (
            "ledger_closing", "bank_reconciliation", "ledger_fx_payment",
            "ledger_analysis", "payment_reminder_bundle"):
        return {
            "task_type": "unsupported",
            "action": action,
            "language": language,
            "entities": {},
            "fields": {"unsupported_reason": entity},
            "raw_prompt": text,
        }

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
            name = extract_customer_name_for_invoice(text)
            if not name:
                name = extract_entity_name(text, "customer")
            entities["customer"] = {"name": name or "Unknown"}
        org_num = extract_org_number(text)
        if org_num:
            fields["org_number"] = org_num

        addr_m = re.search(
            r'(?:[Aa]dress(?:en?|e)|[Aa]ddress|[Dd]irecci[oó]n'
            r'|[Ee]ndere[cç]o|[Aa]nschrift)\s+'
            r'(?:er|ist|is|es|est|\u00e9|:)\s+'
            r'(.+?)(?:\.\s|$)',
            text)
        if addr_m:
            fields["address"] = addr_m.group(1).strip()

    elif entity == "supplier":
        task_type = f"{action}_supplier"
        supp_m = re.search(
            rf'(?:leverand\u00f8r(?:en)?|supplier|vendor|lieferant(?:en)?'
            rf'|fournisseur|proveedor|fornecedor)\s+'
            rf'([{UC}][{UC}{LC}\w\s&.\-]+?)'
            rf'(?:\s*[\(,\.]|\s+(?:med|with|con|mit|avec|com)\s|$)',
            text, re.IGNORECASE)
        if supp_m:
            name = supp_m.group(1).strip()
        else:
            name = extract_entity_name(text, "supplier")
            if not name:
                name = extract_customer_name_for_invoice(text)
        entities["supplier"] = {"name": name or "Unknown"}
        org_num = extract_org_number(text)
        if org_num:
            fields["org_number"] = org_num

    elif entity == "credit_note":
        task_type = "create_credit_note"
        customer_name = extract_customer_name_for_invoice(text)
        entities["credit_note"] = {"customer_name": customer_name}
        org_num = extract_org_number(text)
        if org_num:
            fields["org_number"] = org_num

    elif entity == "product":
        task_type = f"{action}_product"
        all_names = extract_all_quoted_names(text)
        if len(all_names) > 1:
            entities["items"] = [{"name": n} for n in all_names]
        else:
            name = extract_entity_name(text, "product")
            entities["product"] = {"name": name or "Unknown"}

        pn = re.search(
            r'(?:produkt?nummer|product\s*(?:number|no\.?|#)|'
            r'num[eé]ro\s+de\s+produi?t[oa]?|numero\s+de\s+producto|'
            r'n[uú]mero\s+de\s+producto|varenummer)\s*:?\s*(\d+)',
            text, re.IGNORECASE)
        if pn:
            fields["product_number"] = pn.group(1)

        pm = re.search(
            r'(\d[\d\s]*\d)\s*(?:kr|NOK)\s*'
            r'(?:hors|excl|ekskl|exkl|ex|uten|sin|ohne|sans)',
            text, re.IGNORECASE)
        if not pm:
            pm = re.search(
                r'(?:pris|price|prix|precio|Preis)\s*'
                r'(?:er|est|is|es)?\s*(?:de|av|of|:)?\s*'
                r'(\d[\d\s]*[,.]?\d*)\s*(?:kr|NOK)',
                text, re.IGNORECASE)
        if pm:
            fields["price"] = float(
                pm.group(1).replace(" ", "").replace(",", "."))

        vm = re.search(r'(\d+)\s*%', text)
        if vm:
            fields["vat_rate"] = int(vm.group(1))

    elif entity == "project":
        task_type = f"{action}_project"
        proj_m = re.search(
            r'(?:project|prosjekt|proyecto|projekt|projet|projeto)\s+'
            r'"([^"]+)"',
            text, re.IGNORECASE)
        if proj_m:
            name = proj_m.group(1).strip()
        else:
            name = extract_entity_name(text, "project")
        customer_name = extract_project_customer_name(text)
        if not customer_name:
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
        desc = extract_entity_name(text, "travel_expense")
        entities["travel_expense"] = {"description": desc}

        first_name, last_name = extract_person_name(text)
        if first_name != "Unknown":
            fields["employee_first_name"] = first_name
            fields["employee_last_name"] = last_name

        dur_m = re.search(
            r'(\d+)\s*(?:dag(?:ar|er)?|days?|jours?|d\u00edas?|Tage?|dias?)',
            text, re.IGNORECASE)
        if dur_m:
            fields["duration_days"] = int(dur_m.group(1))

        pd_m = re.search(
            r'(?:taxa\s+di\u00e1ria|dagpenger|daglig|daily\s+rate'
            r'|taux\s+journalier|dietas?|Tagessatz|dagsats)'
            r'\s*:?\s*(?:de\s+)?(\d[\d\s]*)\s*(?:kr|NOK)',
            text, re.IGNORECASE)
        if pd_m:
            fields["per_diem_rate"] = float(pd_m.group(1).replace(" ", ""))

        expense_items = []
        expense_section = re.search(
            r'(?:[Dd]espesas|[Ee]xpenses|[Uu]tgifter|[Kk]ostnader'
            r'|[Aa]usgaben|[Aa]uslagen|[Dd]\u00e9penses|[Gg]astos)\s*:?\s*(.+)',
            text, re.DOTALL)
        if expense_section:
            exp_text = expense_section.group(1)
            items_found = re.findall(
                r'([\w\s]+?)\s+(\d[\d\s]*)\s*(?:kr|NOK)',
                exp_text, re.IGNORECASE)
            for exp_name, amount_str in items_found:
                clean_name = re.sub(
                    r'^(?:og|and|y|e|et|und|,)\s+', '',
                    exp_name.strip(), flags=re.IGNORECASE).strip()
                if clean_name:
                    expense_items.append({
                        "description": clean_name,
                        "amount": float(amount_str.replace(" ", "")),
                    })
        if expense_items:
            fields["expenses"] = expense_items

    elif entity == "department":
        task_type = f"{action}_department"
        all_names = extract_all_quoted_names(text)
        if len(all_names) > 1:
            entities["items"] = [{"name": n} for n in all_names]
        else:
            name = extract_entity_name(text, "department")
            entities["department"] = {"name": name or "Unknown"}

    elif entity == "supplier_invoice":
        task_type = "create_supplier_invoice"
        supp_m = re.search(
            rf'(?:leverand\u00f8r(?:en)?|supplier|vendor|lieferant(?:en)?'
            rf'|fournisseur|proveedor|fornecedor)\s+'
            rf'([{UC}][{UC}{LC}\w\s&.\-]+?)'
            rf'(?:\s*[\(,\.]|\s+(?:med|with|con|mit|avec|com|\u00fcber|over|om)\s|$)',
            text, re.IGNORECASE)
        supplier_name = supp_m.group(1).strip() if supp_m else None
        if not supplier_name:
            supplier_name = extract_customer_name_for_invoice(text)
        supplier_name = sanitize_supplier_name(supplier_name)

        org_num = extract_org_number(text)

        inv_num_m = re.search(
            r'((?:INV|FAK|FAKT)[-\s]?\d{4}[-\s]?\d+)', text)
        inv_number = inv_num_m.group(1) if inv_num_m else None

        amount_m = re.search(
            r'(?:\u00fcber|over|om|for|por|pour|of|p\u00e5)\s+'
            r'(\d[\d\s]*)\s*(?:kr|NOK)',
            text, re.IGNORECASE)
        total_amount = None
        if amount_m:
            total_amount = float(amount_m.group(1).replace(" ", ""))

        acct_m = re.search(
            r'(?:[Kk]onto|[Aa]ccount|[Cc]uenta|[Cc]ompte|[Cc]onta)'
            r'\s*(?:nummer|number|no\.?)?\s*(\d{4})',
            text)
        account = acct_m.group(1) if acct_m else None

        vat_m = re.search(r'(\d+)\s*%', text)
        vat_rate = int(vat_m.group(1)) if vat_m else None

        entities["supplier_invoice"] = {
            "supplier_name": supplier_name,
            "invoice_number": inv_number,
            "total_amount": total_amount,
        }
        if org_num:
            fields["org_number"] = org_num
        if account:
            fields["account"] = account
        if vat_rate is not None:
            fields["vat_rate"] = vat_rate

    elif entity == "payment":
        task_type = "register_payment"
        customer_name = extract_customer_name_for_invoice(text)
        org_num = extract_org_number(text)

        amount_m = re.search(
            r'(\d[\d\s]*)\s*(?:kr|NOK)\s*'
            r'(?:hors|excl|ekskl|exkl|ex|uten|sin|ohne|sans)',
            text, re.IGNORECASE)
        if not amount_m:
            amount_m = re.search(
                r'(\d[\d\s]*)\s*(?:kr|NOK)', text, re.IGNORECASE)
        amount = None
        if amount_m:
            amount = float(amount_m.group(1).replace(" ", ""))

        product_name = extract_entity_name(text, "payment")

        entities["payment"] = {
            "customer_name": customer_name,
            "amount": amount,
            "product_name": product_name,
        }
        if org_num:
            fields["org_number"] = org_num
        if re.search(
                r'(?:reverse|revert|storn|tilbakef\u00f8r|annul|retur'
                r'|returned|returnert)',
                text, re.IGNORECASE):
            fields["is_reversal"] = True

    elif entity == "salary":
        task_type = "process_salary"
        first_name, last_name = extract_person_name(text)
        if first_name != "Unknown":
            fields["employee_first_name"] = first_name
            fields["employee_last_name"] = last_name

        base_m = re.search(
            r'(?:sal\u00e1rio\s+base|base\s+salary|grunnl\u00f8nn|salario\s+base'
            r'|salaire\s+de\s+base|grundgehalt)\s*'
            r'(?:er|est|is|es|de|\u00e9)?\s*(?:de\s+)?'
            r'(\d[\d\s]*)\s*(?:kr|NOK)',
            text, re.IGNORECASE)
        if base_m:
            fields["base_salary"] = float(
                base_m.group(1).replace(" ", ""))

        bonus_m = re.search(
            r'(?:b[oó]nus|bonus|tillegg|prime|gratificaci[oó]n)\s*'
            r'(?:\u00fanico|unique|engangs?)?\s*'
            r'(?:de\s+|av\s+|of\s+|von\s+)?'
            r'(\d[\d\s]*)\s*(?:kr|NOK)',
            text, re.IGNORECASE)
        if bonus_m:
            fields["bonus"] = float(bonus_m.group(1).replace(" ", ""))

        entities["salary"] = {
            "first_name": first_name,
            "last_name": last_name,
        }

    elif entity == "expense_receipt":
        task_type = "book_expense_receipt"
        entities["expense_receipt"] = {"description": "Receipt expense"}
        dm = re.search(
            r"(?:avdeling|department)\s+([A-Za-zÆØÅæøåÄÖäöÜüÉéÈèÀà\-]+)",
            text, re.IGNORECASE)
        if dm:
            fields["department_name"] = dm.group(1).strip()
        qm = re.findall(r'"([^"]+)"', text)
        if qm:
            for q in qm:
                if len(q) > 2 and q[0].isupper():
                    fields["department_name"] = fields.get(
                        "department_name") or q
                    break
        am = re.search(
            r'(\d[\d\s]*)\s*(?:kr|NOK)\b', text, re.IGNORECASE)
        if am:
            fields["amount"] = float(am.group(1).replace(" ", ""))
        if re.search(r"togbillett|train|flight|fly", text, re.IGNORECASE):
            fields["expense_account_guess"] = "7140"
        else:
            fields["expense_account_guess"] = "7100"

    elif entity == "dimension":
        task_type = "create_dimension_voucher"
        quotes = extract_all_quoted_names(text)
        dim_name = None
        dim_values = []
        if quotes:
            dim_name = quotes[0]
            if len(quotes) > 1:
                dim_values = quotes[1:]
        if not dim_name:
            dim_m = re.search(
                r'(?:dimensjon|dimension)\s+"([^"]+)"',
                text, re.IGNORECASE)
            if dim_m:
                dim_name = dim_m.group(1).strip()

        acc_m = re.search(
            r'(?:konto|account|cuenta|compte)\s+(\d{3,6})\b',
            text, re.IGNORECASE)
        if acc_m:
            fields["account_number"] = acc_m.group(1)

        amt_m = re.search(
            r'(\d[\d\s]*)\s*(?:kr|NOK)\b',
            text, re.IGNORECASE)
        if amt_m:
            fields["amount"] = float(amt_m.group(1).replace(" ", ""))

        link_m = re.search(
            r'(?:dimensjonsverdien|dimensjonsverdi|dimension\s+value'
            r'|valeur\s+de\s+dimension)\s+"([^"]+)"',
            text, re.IGNORECASE)
        if link_m:
            fields["posting_dimension_label"] = link_m.group(1).strip()
        elif dim_values:
            fields["posting_dimension_label"] = dim_values[0]

        entities["dimension"] = {
            "name": dim_name or "Dimension",
            "values": dim_values,
        }

    elif entity == "order":
        task_type = f"{action}_order"
        customer_name = extract_customer_name_for_invoice(text)
        invoice_lines = extract_invoice_lines(text)
        org_num = extract_org_number(text)
        entities["order"] = {
            "customer_name": customer_name,
            "lines": invoice_lines,
        }
        if customer_name:
            fields["customer_name"] = customer_name
        if org_num:
            fields["org_number"] = org_num
        if re.search(
                r'(?:convert|convertir|convertissez|konverter'
                r'|konvertieren|transformer|gjør\s+om|factur)',
                text, re.IGNORECASE):
            fields["convert_to_invoice"] = True
        if re.search(
                r'(?:payment|paiement|pago|pagamento|betaling|zahlung'
                r'|innbetaling|enregistr|register)',
                text, re.IGNORECASE):
            fields["register_payment"] = True

    return {
        "task_type": task_type,
        "action": action,
        "language": language,
        "entities": entities,
        "fields": fields,
        "raw_prompt": text,
    }
PYEOF

cat > ~/tripletex_agent/app/orchestrator.py << 'PYEOF'
"""Orchestrator v19 - credit note invoice date range, customer filter.

Sandbox discoveries applied:
- employee.companyId → company ID (was trying /company/1-9)
- POST /travelExpense: only employee+title (no date fields)
- POST /travelExpense/cost: amountCurrencyIncVat + paymentType
- Per diem: add as cost lines (rate * days); do NOT use perDiemCompensation
  (only for reiseregning; simple POST creates ansattutlegg)
- POST /supplier: dedicated endpoint (was using /customer)
- POST /ledger/voucher: row >= 1, account lookup by number, supplier ref on AP
- _create_product_safe: handles duplicate name AND number
- Supplier invoice via voucher (expense account + AP 2400)
"""
import hashlib
import json
import sys
import time
import traceback
from datetime import date, timedelta


def log_json(event, **kwargs):
    try:
        msg = json.dumps(
            {"event": event, **kwargs}, default=str, ensure_ascii=False)
        print(msg, file=sys.stdout, flush=True)
    except Exception:
        pass


def _ensure_department(client):
    """Get existing or create a default department."""
    try:
        data = client.get("/department", params={"count": 1})
        items = []
        if isinstance(data, dict) and "values" in data:
            items = data["values"]
        elif isinstance(data, list):
            items = data
        if items:
            return items[0].get("id")
    except Exception:
        pass
    try:
        dept = client.post("/department", {"name": "Generell"})
        return dept.get("id") if isinstance(dept, dict) else None
    except Exception:
        return None


def _find_or_create_employee(client, first_name, last_name,
                              email=None, dept_id=None):
    """Find existing employee by email or create new one."""
    if email:
        try:
            data = client.get("/employee", params={"email": email, "count": 1})
            items = []
            if isinstance(data, dict) and "values" in data:
                items = data["values"]
            elif isinstance(data, list):
                items = data
            if items:
                eid = items[0].get("id")
                if eid:
                    log_json("employee_found", id=eid, email=email)
                    return eid
        except Exception:
            pass

    payload = {
        "firstName": first_name,
        "lastName": last_name,
        "userType": "STANDARD",
    }
    if email:
        payload["email"] = email
    if dept_id:
        payload["department"] = {"id": dept_id}

    try:
        emp = client.post("/employee", payload)
        eid = emp.get("id") if isinstance(emp, dict) else None
        log_json("employee_created_helper", id=eid)
        return eid
    except Exception as e:
        log_json("employee_create_failed", error=str(e)[:200])
        if email:
            try:
                payload.pop("email", None)
                emp = client.post("/employee", payload)
                eid = emp.get("id") if isinstance(emp, dict) else None
                return eid
            except Exception:
                pass
    return None


def _response_values(data):
    """Normalize list from Tripletex GET (values wrapper or raw list)."""
    if isinstance(data, dict) and "values" in data:
        return data["values"]
    if isinstance(data, list):
        return data
    return []


def _invoice_customer_id(inv):
    """Resolve customer id from invoice object."""
    if not isinstance(inv, dict):
        return None
    for key in ("customer", "invoiceCustomer"):
        c = inv.get(key)
        if isinstance(c, dict) and c.get("id"):
            return c.get("id")
    return None


def _find_customer_id(client, org_num, customer_name):
    """Resolve customer id by org number (preferred) or name."""
    if org_num:
        try:
            data = client.get(
                "/customer",
                params={"organizationNumber": str(org_num), "count": 50})
            items = _response_values(data)
            if items:
                cid = items[0].get("id")
                if cid:
                    log_json("customer_found_by_org", id=cid)
                    return cid
        except Exception:
            pass
    if customer_name:
        try:
            data = client.get(
                "/customer",
                params={"name": customer_name.strip(), "count": 50})
            items = _response_values(data)
            cnl = customer_name.strip().lower()
            for it in items:
                if (it.get("name") or "").strip().lower() == cnl:
                    cid = it.get("id")
                    if cid:
                        log_json("customer_found_by_name", id=cid)
                        return cid
            if items:
                cid = items[0].get("id")
                if cid:
                    log_json("customer_found_by_name_fuzzy", id=cid)
                    return cid
        except Exception:
            pass
    return None


def _find_open_invoice_for_amount(client, customer_id, target_amount):
    """Find an invoice for customer matching amount (ex VAT NOK) or outstanding."""
    if not customer_id or not target_amount:
        return None, None
    target = float(target_amount)
    param_sets = [
        {"customerId": customer_id, "count": 100},
        {"invoiceCustomerId": customer_id, "count": 100},
    ]
    for params in param_sets:
        try:
            data = client.get("/invoice", params=params)
            invoices = _response_values(data)
            if not invoices:
                continue
            best = None
            best_diff = None
            for inv in invoices:
                iid = inv.get("id")
                if not iid:
                    continue
                out = inv.get("amountOutstanding")
                amt = inv.get("amount")
                aex = inv.get("amountExcludingVat")
                for cand in (out, amt, aex):
                    if cand is None:
                        continue
                    try:
                        cf = float(cand)
                    except (TypeError, ValueError):
                        continue
                    diff = abs(cf - target)
                    if diff < max(1.0, target * 0.03):
                        log_json(
                            "invoice_amount_match",
                            invoice_id=iid, candidate=cand, target=target)
                        return iid, cf
                    if best_diff is None or diff < best_diff:
                        best_diff = diff
                        best = (iid, cf)
            # Any invoice with outstanding > 0
            for inv in invoices:
                out = inv.get("amountOutstanding")
                if out is None:
                    continue
                try:
                    if float(out) > 0:
                        iid = inv.get("id")
                        if iid:
                            log_json(
                                "invoice_open_fallback",
                                invoice_id=iid, outstanding=out)
                            return iid, float(out)
                except (TypeError, ValueError):
                    continue
            if best and best[0]:
                log_json(
                    "invoice_closest_amount",
                    invoice_id=best[0], amount=best[1], target=target)
                return best[0], best[1]
        except Exception as e:
            log_json("invoice_search_error", error=str(e)[:200])
            continue
    return None, None


def _lookup_account_id(client, account_number):
    """Look up ledger account ID by account number (e.g., '1920')."""
    try:
        data = client.get("/ledger/account",
                          params={"number": account_number, "count": 1})
        items = []
        if isinstance(data, dict) and "values" in data:
            items = data["values"]
        elif isinstance(data, list):
            items = data
        if items:
            return items[0].get("id")
    except Exception:
        pass
    return None


def _ensure_bank_account(client):
    """Try to set bank account via employee.companyId -> PUT /company."""
    cid = None
    try:
        data = client.get("/employee",
                          params={"count": 1, "fields": "id,companyId"})
        items = []
        if isinstance(data, dict) and "values" in data:
            items = data["values"]
        elif isinstance(data, list):
            items = data
        if items:
            cid = items[0].get("companyId")
            if cid:
                log_json("company_id_found", company_id=cid)
    except Exception:
        pass

    if not cid:
        log_json("bank_no_company_id")
        return

    try:
        client.put(f"/company/{cid}", {
            "id": cid,
            "name": "Company",
            "bankAccountNumber": "15032457284",
        })
        log_json("bank_account_set", company_id=cid)
    except Exception as e:
        log_json("bank_put_error", error=str(e)[:200])


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

    extra_text = ""
    if files:
        try:
            from app.schemas import SolveFile
            from app.file_handler import decode_files

            decoded = decode_files([SolveFile(**f) for f in files])
            extra_text = "\n".join(
                (d.get("extracted_text") or "") for d in decoded)
            if extra_text:
                log_json("pdf_text_merged", chars=len(extra_text))
        except Exception as e:
            log_json("file_decode_error", error=str(e)[:200])

    from app.prompt_parser import parse_prompt
    intent = parse_prompt(prompt, extra_text if extra_text else None)

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
    fields = dict(intent.get("fields", {}))
    dept_id = _ensure_department(client)

    items = entities.get("items", [])
    if items:
        for item in items:
            fn = item.get("first_name", "Unknown")
            ln = item.get("last_name", "Unknown")
            em = fields.get("email")
            if not em:
                h = hashlib.md5(
                    (fn + ln + str(fields)).encode("utf-8", errors="ignore")
                ).hexdigest()[:14]
                em = f"employee.{h}@example.com"
            eid = _find_or_create_employee(
                client, fn, ln, email=em, dept_id=dept_id)
            log_json("employee_created", id=eid,
                     name=f"{item.get('first_name')} {item.get('last_name')}")
        return

    emp = entities.get("employee", {})
    fn = emp.get("first_name", "Unknown")
    ln = emp.get("last_name", "Unknown")
    email = fields.get("email")
    if not email:
        h = hashlib.md5(
            (fn + ln + str(fields)).encode("utf-8", errors="ignore")
        ).hexdigest()[:14]
        email = f"employee.{h}@example.com"
    eid = _find_or_create_employee(
        client, fn, ln, email=email, dept_id=dept_id)
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
    if fields.get("org_number"):
        payload["organizationNumber"] = fields["org_number"]
    if fields.get("phone"):
        payload["phoneNumber"] = fields["phone"]
    if fields.get("address"):
        payload["physicalAddress"] = {"addressLine1": fields["address"]}

    result = client.post("/customer", payload)
    cid = result.get("id") if isinstance(result, dict) else None
    log_json("customer_created", id=cid)


def _create_product_safe(client, payload):
    """Create product, handling duplicate name/number gracefully."""
    try:
        result = client.post("/product", payload)
        return result.get("id") if isinstance(result, dict) else None
    except Exception as e:
        err = str(e)
        if "allerede" in err or "already" in err.lower() or "i bruk" in err:
            name = payload.get("name", "")
            number = payload.get("number")
            if number:
                try:
                    data = client.get("/product",
                                      params={"number": str(number),
                                              "count": 1})
                    items = []
                    if isinstance(data, dict) and "values" in data:
                        items = data["values"]
                    if items:
                        return items[0].get("id")
                except Exception:
                    pass
                payload_copy = {k: v for k, v in payload.items()
                                if k != "number"}
                try:
                    result = client.post("/product", payload_copy)
                    return result.get("id") if isinstance(
                        result, dict) else None
                except Exception:
                    pass
            if name:
                try:
                    data = client.get("/product",
                                      params={"name": name, "count": 1})
                    items = []
                    if isinstance(data, dict) and "values" in data:
                        items = data["values"]
                    if items:
                        return items[0].get("id")
                except Exception:
                    pass
        log_json("product_create_error", error=err[:200])
        return None


def _handle_create_product(intent, client):
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})

    items = entities.get("items", [])
    if items:
        for item in items:
            pid = _create_product_safe(
                client, {"name": item.get("name", "Unknown")})
            log_json("product_created", id=pid, name=item.get("name"))
        return

    prod = entities.get("product", {})
    payload = {"name": prod.get("name", "Unknown")}

    if fields.get("product_number"):
        payload["number"] = int(fields["product_number"])
    if fields.get("price"):
        payload["priceExcludingVatCurrency"] = fields["price"]

    if fields.get("vat_rate") is not None:
        vat_map = _get_vat_types(client)
        vat_id = vat_map.get(fields["vat_rate"])
        if vat_id:
            payload["vatType"] = {"id": vat_id}

    pid = _create_product_safe(client, payload)
    log_json("product_created", id=pid, payload_keys=list(payload.keys()))


def _handle_create_project(intent, client):
    proj = intent.get("entities", {}).get("project", {})
    fields = intent.get("fields", {})

    today = str(date.today())
    payload = {
        "name": proj.get("name", "Unknown"),
        "startDate": fields.get("start_date") or today,
    }

    customer_name = fields.get("customer_name")
    if customer_name:
        cust_payload = {"name": customer_name, "isCustomer": True}
        org_num = fields.get("org_number")
        if org_num:
            cust_payload["organizationNumber"] = org_num
        try:
            cust = client.post("/customer", cust_payload)
            cid = cust.get("id") if isinstance(cust, dict) else None
            if cid:
                payload["customer"] = {"id": cid}
        except Exception as e:
            log_json("project_customer_error", error=str(e)[:200])

    mgr_first = fields.get("manager_first_name")
    mgr_last = fields.get("manager_last_name")
    if mgr_first and mgr_last:
        dept_id = _ensure_department(client)
        eid = _find_or_create_employee(
            client, mgr_first, mgr_last,
            email=fields.get("manager_email"),
            dept_id=dept_id)
        if eid:
            payload["projectManager"] = {"id": eid}

    if "projectManager" not in payload:
        try:
            data = client.get("/employee", params={"count": 1})
            items = []
            if isinstance(data, dict) and "values" in data:
                items = data["values"]
            elif isinstance(data, list):
                items = data
            if items:
                fallback_id = items[0].get("id")
                if fallback_id:
                    payload["projectManager"] = {"id": fallback_id}
                    log_json("project_manager_fallback", id=fallback_id)
        except Exception:
            pass

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

    _ensure_bank_account(client)

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

    pid = _create_product_safe(client, prod_payload)

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


def _handle_create_travel_expense(intent, client):
    """Create a travel expense report with costs."""
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})

    dept_id = _ensure_department(client)
    first_name = fields.get("employee_first_name", "Unknown")
    last_name = fields.get("employee_last_name", "Unknown")
    email = fields.get("email")
    eid = _find_or_create_employee(client, first_name, last_name,
                                    email=email, dept_id=dept_id)
    if not eid:
        log_json("travel_no_employee")
        return

    te_desc = (entities.get("travel_expense", {}).get("description")
               or "Travel expense")
    today = str(date.today())

    te_id = None
    try:
        te = client.post("/travelExpense", {
            "employee": {"id": eid},
            "title": te_desc,
        })
        te_id = te.get("id") if isinstance(te, dict) else None
        log_json("travel_expense_created", id=te_id)
    except Exception as e:
        log_json("travel_create_error", error=str(e)[:300])

    if not te_id:
        return

    pt_id = None
    try:
        pt_data = client.get("/travelExpense/paymentType",
                             params={"count": 1})
        pt_items = []
        if isinstance(pt_data, dict) and "values" in pt_data:
            pt_items = pt_data["values"]
        elif isinstance(pt_data, list):
            pt_items = pt_data
        if pt_items:
            pt_id = pt_items[0].get("id")
    except Exception:
        pass

    expenses = list(fields.get("expenses") or [])
    per_diem = fields.get("per_diem_rate")
    duration = int(fields.get("duration_days") or 1)
    if per_diem and duration > 0:
        total_pd = float(per_diem) * duration
        expenses.append({
            "description": "Dagpenger / per diem",
            "amount": total_pd,
        })

    for exp in expenses:
        cost_payload = {
            "travelExpense": {"id": te_id},
            "date": today,
            "amountCurrencyIncVat": exp.get("amount", 0),
        }
        if pt_id:
            cost_payload["paymentType"] = {"id": pt_id}
        try:
            client.post("/travelExpense/cost", cost_payload)
            log_json("travel_cost_added",
                     desc=exp.get("description"),
                     amount=exp.get("amount"))
        except Exception as e:
            log_json("travel_cost_error", error=str(e)[:200])


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


def _handle_create_supplier(intent, client):
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})

    supp = entities.get("supplier", {})
    name = supp.get("name", "Unknown")
    payload = {"name": name, "isSupplier": True}

    org_num = fields.get("org_number")
    if org_num:
        payload["organizationNumber"] = org_num
    if fields.get("email"):
        payload["email"] = fields["email"]
    if fields.get("phone"):
        payload["phoneNumber"] = fields["phone"]

    sid = None
    try:
        result = client.post("/supplier", payload)
        sid = result.get("id") if isinstance(result, dict) else None
    except Exception:
        try:
            result = client.post("/customer", payload)
            sid = result.get("id") if isinstance(result, dict) else None
        except Exception as e:
            log_json("supplier_create_error", error=str(e)[:200])
    log_json("supplier_created", id=sid, name=name)


def _handle_credit_note(intent, client):
    """Find existing invoice(s) and create credit note(s)."""
    fields = intent.get("fields", {})
    entities = intent.get("entities", {})
    cn = entities.get("credit_note", {})
    customer_name = cn.get("customer_name")
    org_num = fields.get("org_number")

    d0 = (date.today() - timedelta(days=1095)).isoformat()
    d1 = date.today().isoformat()
    params = {
        "count": 200,
        "invoiceDateFrom": d0,
        "invoiceDateTo": d1,
    }
    try:
        data = client.get("/invoice", params=params)
        invoices = _response_values(data)

        cid = None
        if org_num:
            cid = _find_customer_id(client, org_num, customer_name)
        if cid and invoices:
            filt = [
                inv for inv in invoices
                if _invoice_customer_id(inv) == cid
            ]
            if filt:
                invoices = filt
                log_json("credit_note_filtered", customer_id=cid, n=len(filt))
            else:
                log_json("credit_note_no_match_customer", customer_id=cid)

        if not invoices:
            log_json("credit_note_no_invoices")
            return

        for inv in invoices:
            inv_id = inv.get("id")
            if inv_id:
                try:
                    result = client.post(
                        f"/invoice/{inv_id}/:createCreditNote", {})
                    cn_id = (result.get("id")
                             if isinstance(result, dict) else None)
                    log_json("credit_note_created",
                             invoice_id=inv_id, credit_note_id=cn_id)
                    return
                except Exception as e:
                    log_json("credit_note_error",
                             invoice_id=inv_id, error=str(e)[:200])
    except Exception as e:
        log_json("credit_note_search_error", error=str(e)[:200])


def _handle_create_order(intent, client):
    """Create order, optionally convert to invoice and register payment."""
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})
    order_ent = entities.get("order", {})

    _ensure_bank_account(client)

    customer_name = (order_ent.get("customer_name")
                     or fields.get("customer_name"))
    if not customer_name:
        log_json("order_no_customer")
        return

    cust_payload = {"name": customer_name, "isCustomer": True}
    org_num = fields.get("org_number")
    if org_num:
        cust_payload["organizationNumber"] = org_num

    cust = client.post("/customer", cust_payload)
    customer_id = cust.get("id") if isinstance(cust, dict) else None
    if not customer_id:
        log_json("order_customer_failed")
        return

    vat_map = _get_vat_types(client)
    raw_lines = order_ent.get("lines") or []
    order_lines = []
    for raw_line in raw_lines:
        ol = _build_order_line(raw_line, client, vat_map)
        if ol:
            order_lines.append(ol)

    if not order_lines:
        prod = client.post("/product", {"name": "Product"})
        pid = prod.get("id") if isinstance(prod, dict) else None
        if pid:
            order_lines.append({
                "product": {"id": pid},
                "count": 1,
                "unitPriceExcludingVatCurrency": 100.0,
            })

    today = str(date.today())
    order = client.post("/order", {
        "customer": {"id": customer_id},
        "orderDate": today,
        "deliveryDate": today,
        "orderLines": order_lines,
    })
    order_id = order.get("id") if isinstance(order, dict) else None
    log_json("order_created", id=order_id)

    if not order_id:
        return

    if fields.get("convert_to_invoice"):
        try:
            inv = client.post("/invoice", {
                "invoiceDate": today,
                "invoiceDueDate": today,
                "customer": {"id": customer_id},
                "orders": [{"id": order_id}],
            })
            inv_id = inv.get("id") if isinstance(inv, dict) else None
            log_json("order_invoice_created", id=inv_id)

            if fields.get("register_payment") and inv_id:
                try:
                    inv_data = client.get(f"/invoice/{inv_id}")
                    amount = 0
                    if isinstance(inv_data, dict):
                        amount = (inv_data.get("amountOutstanding")
                                  or inv_data.get("amount") or 0)
                except Exception:
                    amount = 0

                for pay_ep, pay_body in [
                    (f"/invoice/{inv_id}/:payment",
                     {"paymentDate": today, "paymentTypeId": 0,
                      "paidAmount": amount}),
                    (f"/invoice/{inv_id}/:createPayment",
                     {"paymentDate": today, "paidAmount": amount}),
                    ("/payment",
                     {"paymentDate": today, "amount": amount,
                      "invoice": {"id": inv_id}}),
                ]:
                    try:
                        client.post(pay_ep, pay_body)
                        log_json("payment_registered",
                                 invoice_id=inv_id, amount=amount,
                                 endpoint=pay_ep)
                        break
                    except Exception as e:
                        log_json("payment_try",
                                 endpoint=pay_ep,
                                 error=str(e)[:150])
        except Exception as e:
            log_json("order_invoice_error", error=str(e)[:200])


def _handle_supplier_invoice(intent, client):
    """Record a received supplier invoice via voucher."""
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})
    si = entities.get("supplier_invoice", {})

    supplier_name = si.get("supplier_name") or "Unknown"
    org_num = fields.get("org_number")
    total_amount = si.get("total_amount") or 0
    inv_number = si.get("invoice_number")
    account = fields.get("account") or "6590"
    vat_rate = fields.get("vat_rate")

    supp_payload = {"name": supplier_name, "isSupplier": True}
    if org_num:
        supp_payload["organizationNumber"] = org_num
    if fields.get("email"):
        supp_payload["email"] = fields["email"]

    supp_id = None
    try:
        supp = client.post("/supplier", supp_payload)
        supp_id = supp.get("id") if isinstance(supp, dict) else None
        log_json("supplier_for_invoice_created", id=supp_id)
    except Exception:
        try:
            supp = client.post("/customer", supp_payload)
            supp_id = supp.get("id") if isinstance(supp, dict) else None
        except Exception as e:
            log_json("supplier_create_error", error=str(e)[:200])

    today = str(date.today())

    expense_acc_id = _lookup_account_id(client, account)
    ap_acc_id = _lookup_account_id(client, "2400")

    if not expense_acc_id or not ap_acc_id:
        log_json("supplier_inv_account_lookup_failed",
                 expense=expense_acc_id, ap=ap_acc_id)
        return

    description = (f"Supplier invoice {inv_number or ''}"
                   f" from {supplier_name}").strip()

    postings = [
        {"date": today, "row": 1,
         "account": {"id": expense_acc_id},
         "amountGross": float(total_amount),
         "amountGrossCurrency": float(total_amount)},
        {"date": today, "row": 2,
         "account": {"id": ap_acc_id},
         "amountGross": -float(total_amount),
         "amountGrossCurrency": -float(total_amount)},
    ]
    if supp_id:
        postings[1]["supplier"] = {"id": supp_id}

    try:
        result = client.post("/ledger/voucher", {
            "date": today,
            "description": description,
            "postings": postings,
        })
        rid = result.get("id") if isinstance(result, dict) else None
        log_json("supplier_invoice_voucher", id=rid)
    except Exception as e:
        log_json("supplier_invoice_error", error=str(e)[:200])


def _complete_invoice_payment(client, inv_id, customer_id, pay_amount, today):
    """POST payment endpoints + voucher fallback (shared by new and existing invoice)."""
    try:
        inv_data = client.get(f"/invoice/{inv_id}")
        if isinstance(inv_data, dict):
            pay_amount = (
                inv_data.get("amountOutstanding")
                or inv_data.get("amount") or pay_amount)
    except Exception:
        pass

    pay_ok = False
    for pay_endpoint, pay_body in [
        (f"/invoice/{inv_id}/:payment",
         {"paymentDate": today, "paymentTypeId": 0,
          "paidAmount": pay_amount}),
        (f"/invoice/{inv_id}/:createPayment",
         {"paymentDate": today, "paidAmount": pay_amount}),
        ("/payment",
         {"paymentDate": today, "amount": pay_amount,
          "invoice": {"id": inv_id}}),
        ("/bank/payment",
         {"paymentDate": today, "amount": pay_amount,
          "invoice": {"id": inv_id}}),
    ]:
        try:
            client.post(pay_endpoint, pay_body)
            log_json("payment_registered",
                     invoice_id=inv_id, amount=pay_amount,
                     endpoint=pay_endpoint)
            pay_ok = True
            break
        except Exception as e:
            log_json("payment_try", endpoint=pay_endpoint,
                     error=str(e)[:150])

    if not pay_ok:
        try:
            bank_id = _lookup_account_id(client, "1920")
            ar_id = _lookup_account_id(client, "1500")
            if bank_id and ar_id:
                client.post("/ledger/voucher", {
                    "date": today,
                    "description": f"Payment for invoice {inv_id}",
                    "postings": [
                        {"date": today, "row": 1,
                         "account": {"id": bank_id},
                         "amountGross": float(pay_amount),
                         "amountGrossCurrency": float(pay_amount)},
                        {"date": today, "row": 2,
                         "account": {"id": ar_id},
                         "amountGross": -float(pay_amount),
                         "amountGrossCurrency": -float(pay_amount),
                         "customer": {"id": customer_id}},
                    ],
                })
                log_json("payment_voucher_fallback", invoice_id=inv_id)
            else:
                log_json("payment_account_lookup_failed")
        except Exception as e:
            log_json("payment_all_failed", invoice_id=inv_id,
                     error=str(e)[:150])


def _handle_register_payment(intent, client):
    """Create customer+invoice chain and register full payment."""
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})
    payment = entities.get("payment", {})

    customer_name = (payment.get("customer_name")
                     or fields.get("customer_name"))
    if not customer_name:
        log_json("payment_no_customer")
        return

    _ensure_bank_account(client)

    org_num = fields.get("org_number")
    amount = payment.get("amount") or 100.0
    today = str(date.today())

    cust_id = _find_customer_id(client, org_num, customer_name)
    if cust_id:
        inv_existing, pay_amt_found = _find_open_invoice_for_amount(
            client, cust_id, amount)
        if inv_existing:
            log_json("payment_existing_invoice_chain",
                     invoice_id=inv_existing, customer_id=cust_id)
            _complete_invoice_payment(
                client, inv_existing, cust_id,
                pay_amt_found or amount, today)
            return

    cust_payload = {"name": customer_name, "isCustomer": True}
    if org_num:
        cust_payload["organizationNumber"] = org_num
    cust = client.post("/customer", cust_payload)
    customer_id = cust.get("id") if isinstance(cust, dict) else None
    if not customer_id:
        log_json("payment_customer_failed")
        return

    product_name = payment.get("product_name") or "Product"

    _get_vat_types(client)
    prod = client.post("/product", {"name": product_name})
    pid = prod.get("id") if isinstance(prod, dict) else None

    order_lines = []
    if pid:
        order_lines.append({
            "product": {"id": pid},
            "count": 1,
            "unitPriceExcludingVatCurrency": float(amount),
            "description": product_name,
        })

    order = client.post("/order", {
        "customer": {"id": customer_id},
        "orderDate": today,
        "deliveryDate": today,
        "orderLines": order_lines,
    })
    order_id = order.get("id") if isinstance(order, dict) else None
    if not order_id:
        log_json("payment_order_failed")
        return

    inv = client.post("/invoice", {
        "invoiceDate": today,
        "invoiceDueDate": today,
        "customer": {"id": customer_id},
        "orders": [{"id": order_id}],
    })
    inv_id = inv.get("id") if isinstance(inv, dict) else None
    if not inv_id:
        log_json("payment_invoice_failed")
        return

    _complete_invoice_payment(client, inv_id, customer_id, amount, today)


def _handle_process_salary(intent, client):
    """Process salary: create employee and attempt payslip."""
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})
    salary = entities.get("salary", {})

    first_name = (salary.get("first_name")
                  or fields.get("employee_first_name", "Unknown"))
    last_name = (salary.get("last_name")
                 or fields.get("employee_last_name", "Unknown"))
    email = fields.get("email")

    if first_name in ("Unknown", "Vous", "Creez", "Créez", "") or len(
            str(first_name)) < 2:
        first_name = "Employee"
    if last_name in ("Unknown", "Tripletex", "Creez", "") or len(
            str(last_name)) < 2:
        last_name = "Contract"

    dept_id = _ensure_department(client)
    if not email:
        h = hashlib.md5(
            (first_name + last_name + str(fields)).encode("utf-8", errors="ignore")
        ).hexdigest()[:14]
        email = f"salary.{h}@example.com"

    eid = _find_or_create_employee(
        client, first_name, last_name, email=email, dept_id=dept_id)
    if not eid:
        log_json("salary_no_employee")
        return

    base_salary = fields.get("base_salary", 0)
    bonus = fields.get("bonus", 0)
    today = str(date.today())

    try:
        ps = client.post("/salary/payslip", {
            "employee": {"id": eid},
            "date": today,
        })
        ps_id = ps.get("id") if isinstance(ps, dict) else None
        log_json("payslip_created", id=ps_id)
    except Exception as e:
        log_json("payslip_error", error=str(e)[:200])
        try:
            client.post("/salary/transaction", {
                "employee": {"id": eid},
                "date": today,
                "amount": base_salary + bonus,
                "description": f"Salary {first_name} {last_name}",
            })
            log_json("salary_transaction_created")
        except Exception as e2:
            log_json("salary_fallback_error", error=str(e2)[:200])


def _handle_book_expense_receipt(intent, client):
    """Post expense from receipt (train ticket etc.) via voucher."""
    fields = intent.get("fields", {})
    today = str(date.today())
    amount = float(fields.get("amount") or 0)
    if amount <= 0:
        amount = 500.0
    acc_num = str(fields.get("expense_account_guess") or "7140")
    expense_id = _lookup_account_id(client, acc_num)
    bank_id = _lookup_account_id(client, "1920")
    if not expense_id or not bank_id:
        log_json("expense_receipt_accounts_failed")
        return

    dept_name = fields.get("department_name")
    dept_id = None
    if dept_name:
        try:
            data = client.get("/department", params={"count": 200})
            items = data.get("values", []) if isinstance(data, dict) else []
            for d in items:
                if (d.get("name") or "").strip().lower() == dept_name.strip().lower():
                    dept_id = d.get("id")
                    break
        except Exception:
            pass

    post1 = {
        "date": today,
        "row": 1,
        "account": {"id": expense_id},
        "amountGross": amount,
        "amountGrossCurrency": amount,
        "description": (intent.get("entities", {}).get(
            "expense_receipt", {}).get("description") or "Receipt expense"),
    }
    if dept_id:
        post1["department"] = {"id": dept_id}
    post2 = {
        "date": today,
        "row": 2,
        "account": {"id": bank_id},
        "amountGross": -amount,
        "amountGrossCurrency": -amount,
    }

    try:
        r = client.post("/ledger/voucher", {
            "date": today,
            "description": "Receipt / kvittering",
            "postings": [post1, post2],
        })
        vid = r.get("id") if isinstance(r, dict) else None
        log_json("expense_receipt_voucher", id=vid, dept=dept_id)
    except Exception as e:
        log_json("expense_receipt_error", error=str(e)[:250])


def _handle_dimension_voucher(intent, client):
    """Create a voucher for dimension tasks; optionally register dimension."""
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})
    dim = entities.get("dimension", {})
    today = str(date.today())
    amount = float(fields.get("amount") or 0)
    acc_num = str(fields.get("account_number") or "6340")
    dim_name = dim.get("name") or "Dimension"

    if amount <= 0:
        amount = 100.0

    expense_id = _lookup_account_id(client, acc_num)
    bank_id = _lookup_account_id(client, "1920")
    if not expense_id or not bank_id:
        log_json("dimension_voucher_account_lookup_failed",
                 expense=expense_id, bank=bank_id)
        return

    description = f"{dim_name} — dimension voucher"
    post1 = {
        "date": today,
        "row": 1,
        "account": {"id": expense_id},
        "amountGross": amount,
        "amountGrossCurrency": amount,
    }
    post2 = {
        "date": today,
        "row": 2,
        "account": {"id": bank_id},
        "amountGross": -amount,
        "amountGrossCurrency": -amount,
    }
    label = fields.get("posting_dimension_label")
    if label:
        post1["description"] = f"{description} ({label})"

    try:
        result = client.post("/ledger/voucher", {
            "date": today,
            "description": description,
            "postings": [post1, post2],
        })
        vid = result.get("id") if isinstance(result, dict) else None
        log_json("dimension_voucher_posted", id=vid, dimension=dim_name)
    except Exception as e:
        log_json("dimension_voucher_error", error=str(e)[:250])

    for endpoint, payload in [
        ("/ledger/dimension", {"name": dim_name}),
        ("/dimension", {"name": dim_name}),
    ]:
        try:
            client.post(endpoint, payload)
            log_json("dimension_create_attempt", endpoint=endpoint)
        except Exception:
            pass


_HANDLERS = {
    "create_employee": _handle_create_employee,
    "create_customer": _handle_create_customer,
    "create_product": _handle_create_product,
    "create_project": _handle_create_project,
    "create_invoice": _handle_create_invoice,
    "create_supplier": _handle_create_supplier,
    "create_credit_note": _handle_credit_note,
    "create_travel_expense": _handle_create_travel_expense,
    "delete_travel_expense": _handle_delete_travel,
    "create_department": _handle_create_department,
    "create_order": _handle_create_order,
    "create_supplier_invoice": _handle_supplier_invoice,
    "register_payment": _handle_register_payment,
    "process_salary": _handle_process_salary,
    "create_dimension_voucher": _handle_dimension_voucher,
    "book_expense_receipt": _handle_book_expense_receipt,
}
PYEOF

