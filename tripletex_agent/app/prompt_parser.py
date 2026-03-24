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
    "dimens\u00e3o", "dimensao", "dimensi\u00f3n personalizada",
    "dimensi\u00f3n contable personalizada",
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
    "dans",
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
            r"|provision pour salaires|comptabilisez \u00e9galement"
            r"|\u00e5rsoppgjer|forenkla\s+\u00e5rsoppgjer|avskrivingar",
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
            r"|avstemm(?:ing)?|\bavstem\b|csv\s+anexo|bank\s+statement"
            r"|bankutskrift",
            lower):
        return "bank_reconciliation"

    # Analyze ledger + multiple internal projects / activities (not one create_project)
    if re.search(
            r"analyser hovudboka|finn dei tre|kostnadskontoane|st\u00f8rst auke"
            r"|internt prosjekt|kontoens namn|aktivitet for kvart prosjekt",
            lower):
        return "ledger_analysis"

    # Full project lifecycle (hours, supplier cost, customer invoice) — not create_supplier
    if re.search(
            r"prosjektsyklusen|heile prosjektsyklus|gjennomf\u00f8r heile"
            r"|kundefaktura for prosjektet",
            lower) and re.search(
            r"budsjett|timar|leverand\u00f8rkostnad|prosjektleiar|konsulent",
            lower):
        return "project_lifecycle"

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
    # Norwegian: "Opprett en ordre ... Konverter ordren til faktura ... betaling"
    if re.search(
            r"opprett\s+en\s+ordre|opprette\s+en\s+ordre",
            lower) and re.search(
            r"konverter.*faktura|til\s+faktura|full\s+betaling"
            r"|registrer\s+full\s+betaling",
            lower):
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
            "ledger_analysis", "payment_reminder_bundle",
            "project_lifecycle"):
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
        cam = re.search(
            r"(\d[\d\s]*)\s*(?:kr|NOK|EUR)\s*"
            r"(?:ohne|sans|excl|hors|ekskl|uten|sin)",
            text, re.IGNORECASE)
        if cam:
            fields["credit_note_amount"] = float(
                cam.group(1).replace(" ", "").replace(",", "."))

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
        iam = re.search(
            r"(\d[\d\s]*)\s*(?:kr|NOK)\s*"
            r"(?:hors|excl|ekskl|sans|ohne|uten)",
            text, re.IGNORECASE)
        if iam:
            fields["invoice_amount_ex_vat"] = float(
                iam.group(1).replace(" ", "").replace(",", "."))
        if not invoice_lines and fields.get("invoice_amount_ex_vat"):
            invoice_lines = [{
                "product_name": "Service",
                "quantity": 1,
                "unit_price": fields["invoice_amount_ex_vat"],
                "vat_rate": 25,
            }]
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
