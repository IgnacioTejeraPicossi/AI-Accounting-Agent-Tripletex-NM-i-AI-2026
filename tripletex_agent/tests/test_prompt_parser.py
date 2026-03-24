from app.prompt_parser import detect_language, parse_prompt


def test_parse_employee_en():
    intent = parse_prompt(
        "Create an employee named Ola Nordmann with email ola.nordmann@example.com and phone +47 12345678"
    )
    assert intent.task_type == "create_employee"
    assert intent.entities["employee"]["first_name"] == "Ola"
    assert intent.entities["employee"]["last_name"] == "Nordmann"
    assert intent.fields["email"] == "ola.nordmann@example.com"


def test_parse_customer_en():
    intent = parse_prompt(
        'Create a customer named "Nordic Bakery AS" with email post@nordicbakery.no'
    )
    assert intent.task_type == "create_customer"
    assert "customer" in intent.entities


def test_parse_product_en():
    intent = parse_prompt("Create a product called Consulting Hour")
    assert intent.task_type == "create_product"
    assert "product" in intent.entities


def test_parse_project_en():
    intent = parse_prompt("Create a project named Migration Project for customer Nordic Bakery AS")
    assert intent.task_type == "create_project"
    assert "project" in intent.entities
    assert intent.entities["project"]["name"]


def test_parse_invoice_en():
    intent = parse_prompt(
        "Create an invoice for customer Nordic Bakery AS with one line for Consulting Hour, quantity 2, unit price 1500"
    )
    assert intent.task_type == "create_invoice"
    assert "invoice" in intent.entities


def test_parse_employee_es():
    intent = parse_prompt("Crear un empleado llamado Juan García con email juan@example.com")
    assert intent.task_type == "create_employee"
    assert intent.language == "es"


def test_parse_customer_nb():
    intent = parse_prompt("Opprett en kunde kalt Nordic Bakery AS med epost post@nordicbakery.no")
    assert intent.task_type == "create_customer"
    assert intent.language == "nb"


def test_parse_product_de():
    intent = parse_prompt("Erstellen Sie ein Produkt namens Consulting Hour")
    assert intent.task_type == "create_product"
    assert intent.language == "de"


def test_parse_customer_fr():
    intent = parse_prompt("Créer un client nommé Nordic Bakery AS avec e-mail post@nordicbakery.no")
    assert intent.task_type == "create_customer"
    assert intent.language == "fr"


def test_parse_invoice_nb():
    intent = parse_prompt(
        "Opprett en faktura for kunden Nordic Bakery AS med 2 timer Consulting Hour til 1500 kr"
    )
    assert intent.task_type == "create_invoice"
    assert intent.language == "nb"


def test_detect_language_en():
    assert detect_language("Create an employee named Ola") == "en"


def test_detect_language_es():
    assert detect_language("Crear un empleado llamado Juan") == "es"


def test_detect_language_de():
    assert detect_language("Erstellen Sie einen Mitarbeiter") == "de"


def test_detect_language_fr():
    assert detect_language("Créer un employé nommé Jean") == "fr"


def test_detect_language_nb():
    assert detect_language("Opprett en ansatt med navn Ola") == "nb"


def test_parse_unsupported():
    intent = parse_prompt("Do something weird that doesn't match anything")
    assert intent.task_type == "unsupported"
