"""Quick checks for v15 parser changes."""
from app.prompt_parser import parse_prompt, detect_entity


def test_email_does_not_fake_faktura():
    t = (
        "Registrer leverandøren Fossekraft AS med organisasjonsnummer "
        "977371635. E-post: faktura@fossekraft.no."
    )
    assert detect_entity(t) == "supplier"


def test_salary_pt_processe():
    t = (
        "Processe o salário de Lucas Martins (lucas.martins@example.org) "
        "para este mês."
    )
    assert detect_entity(t) == "salary"


def test_french_order_beats_payment():
    t = (
        "Créez une commande pour le client Forêt SARL (nº org. 962176127) "
        "avec les produits Maintenance (2417) à 32250 NOK. Convertissez la "
        "commande en facture et enregistrez le paiement intégral."
    )
    assert detect_entity(t) == "order"


def test_dimension_nb():
    t = (
        'Opprett ein fri rekneskapsdimensjon "Marked" med verdiane '
        '"Offentlig" og "Privat". Bokfør deretter eit bilag på konto 6340 '
        'for 25200 kr, knytt til dimensjonsverdien "Offentlig".'
    )
    assert detect_entity(t) == "dimension"
    r = parse_prompt(t)
    assert r["task_type"] == "create_dimension_voucher"
    assert r["fields"].get("amount") == 25200.0
    assert r["fields"].get("account_number") == "6340"


def test_v17_month_end_not_salary():
    t = (
        "Gjer månavslutninga for mars 2026. Periodiser forskotsbetalt kostnad. "
        "Bokfør månadleg avskriving. Kontroller at saldobalansen går i null. "
        "Bokfør også ei lønnsavsetjing (debet lønnskostnad konto 5000)."
    )
    assert detect_entity(t) == "ledger_closing"
    r = parse_prompt(t)
    assert r["task_type"] == "unsupported"
    assert r["fields"].get("unsupported_reason") == "ledger_closing"


def test_v17_bank_recon_unsupported():
    t = (
        "Reconcilie o extrato bancario (CSV anexo) com as faturas em aberto "
        "no Tripletex."
    )
    assert detect_entity(t) == "bank_reconciliation"
    assert parse_prompt(t)["task_type"] == "unsupported"


def test_v17_supplier_name_not_se_nao_existir():
    t = (
        "Voce recebeu uma fatura de fornecedor (ver PDF anexo). "
        "Registe a fatura no Tripletex. Crie o fornecedor se nao existir."
    )
    r = parse_prompt(t)
    assert r["task_type"] == "create_supplier_invoice"
    sn = r["entities"].get("supplier_invoice", {}).get("supplier_name")
    assert sn is None or sn not in ("se nao existir", "Se nao existir")


def test_v18_spanish_product_number():
    t = (
        'Crea el producto "Mantenimiento" con número de producto 7266. '
        "El precio es 650 NOK sin IVA, utilizando la tasa estándar del 25 %."
    )
    r = parse_prompt(t)
    assert r["task_type"] == "create_product"
    assert r["fields"].get("product_number") == "7266"
    assert r["fields"].get("price") == 650.0


def test_v18_offer_letter_is_employee_not_salary():
    t = (
        "Has recibido una carta de oferta (ver PDF adjunto) para un nuevo "
        "empleado. Completa la incorporacion: crea el empleado, asigna el "
        "departamento correcto, configura los detalles de empleo con "
        "porcentaje y salario anual."
    )
    assert detect_entity(t) == "employee"
    assert parse_prompt(t)["task_type"] == "create_employee"


def test_v18_french_month_end_not_salary():
    t = (
        "Effectuez la clôture mensuelle de mars 2026. Comptabilisez la "
        "régularisation (14300 NOK par mois du compte 1700 vers charges). "
        "Enregistrez l'amortissement mensuel. Vérifiez que la balance est "
        "à zéro. Comptabilisez également une provision pour salaires."
    )
    assert detect_entity(t) == "ledger_closing"
    assert parse_prompt(t)["task_type"] == "unsupported"


def test_v18_fx_agio_unsupported():
    t = (
        "Vi sendte en faktura på 16689 EUR til Polaris AS (org.nr 957486282) "
        "da kursen var 11.66 NOK/EUR. Kunden har nå betalt, men kursen er "
        "12.24 NOK/EUR. Registrer betalingen og bokfør valutadifferansen "
        "(agio) på korrekt konto."
    )
    assert detect_entity(t) == "ledger_fx_payment"
    assert parse_prompt(t)["fields"].get("unsupported_reason") == "ledger_fx_payment"


def test_v18_project_customer_montana():
    t = (
        'Registre 26 horas para Lucía Martínez (lucia.martinez@example.org) '
        'en la actividad "Utvikling" del proyecto "Desarrollo e-commerce" '
        "para Montaña SL (org. nº 869049328). Tarifa por hora: 1100 NOK/h. "
        "Genere una factura de proyecto al cliente basada en las horas "
        "registradas."
    )
    r = parse_prompt(t)
    assert r["task_type"] == "create_project"
    assert "Montaña" in (r["fields"].get("customer_name") or "")


def test_v19_norwegian_ledger_analysis_unsupported():
    t = (
        "Totalkostnadene auka monaleg frå januar til februar 2026. "
        "Analyser hovudboka og finn dei tre kostnadskontoane med størst auke "
        "i beløp. Opprett eit internt prosjekt for kvar av dei tre kontoane "
        "med kontoens namn."
    )
    assert parse_prompt(t)["fields"].get("unsupported_reason") == "ledger_analysis"


def test_v19_spanish_payment_reminder_unsupported():
    t = (
        "Encuentre la factura vencida y registre un cargo por recordatorio "
        "de 60 NOK. Debito cuentas por cobrar (1500), credito ingresos por "
        "recordatorio (3400). registre un pago parcial de 5000 NOK."
    )
    assert parse_prompt(t)["fields"].get("unsupported_reason") == (
        "payment_reminder_bundle")


def test_v20_norwegian_bank_avstem_unsupported():
    t = (
        "Avstem bankutskrifta (vedlagt CSV) mot opne fakturaer i Tripletex. "
        "Match innbetalingar til kundefakturaer."
    )
    assert parse_prompt(t)["fields"].get("unsupported_reason") == (
        "bank_reconciliation")


def test_v20_portuguese_dimension_not_project():
    t = (
        'Crie uma dimensão contabilística personalizada "Prosjekttype" '
        'com os valores "Internt" e "Forskning". Em seguida, lance um '
        "documento na conta 7000 por 13900 NOK."
    )
    assert detect_entity(t) == "dimension"


def test_v19_french_project_riviere_customer():
    t = (
        "Exécutez le cycle de vie complet du projet 'Migration Cloud Rivière' "
        "(Rivière SARL, nº org. 855961962) : 1) Le projet a un budget de "
        "480500 NOK. 2) Enregistrez le temps : Camille Dubois. "
        "4) Créez une facture client pour le projet."
    )
    r = parse_prompt(t)
    assert r["task_type"] == "create_project"
    cn = r["fields"].get("customer_name") or ""
    assert "Rivière" in cn or "Riviere" in cn


def test_v21_norwegian_order_convert_payment():
    t = (
        "Opprett en ordre for kunden Nordhav AS (org.nr 904923915) med "
        "produktene Konsulenttimer (7493) til 8200 kr og Webdesign (5668) "
        "til 24400 kr. Konverter ordren til faktura og registrer full betaling."
    )
    assert detect_entity(t) == "order"
    assert parse_prompt(t)["task_type"] == "create_order"


def test_v21_german_credit_note_amount():
    t = (
        'Der Kunde Brückentor GmbH (Org.-Nr. 901668566) hat die Rechnung für '
        '"Webdesign" (38800 NOK ohne MwSt.) reklamiert. Erstellen Sie eine '
        "vollständige Gutschrift."
    )
    r = parse_prompt(t)
    assert r["task_type"] == "create_credit_note"
    assert r["fields"].get("credit_note_amount") == 38800.0


def test_v21_norwegian_project_lifecycle_unsupported():
    t = (
        "Gjennomfør heile prosjektsyklusen for 'Skymigrering Sjøbris' "
        "(Sjøbris AS, org.nr 912361152): 1) Prosjektet har budsjett 354050 kr."
    )
    r = parse_prompt(t)
    assert r["task_type"] == "unsupported"
    assert r["fields"].get("unsupported_reason") == "project_lifecycle"
