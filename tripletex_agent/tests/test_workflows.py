from unittest.mock import Mock

from app.schemas import ParsedIntent
from app.workflows.create_customer import CreateCustomerWorkflow
from app.workflows.create_employee import CreateEmployeeWorkflow
from app.workflows.create_invoice import CreateInvoiceWorkflow
from app.workflows.create_product import CreateProductWorkflow
from app.workflows.create_project import CreateProjectWorkflow


# --- Employee ---

def test_create_employee_new():
    workflow = CreateEmployeeWorkflow()
    client = Mock()
    client.create_employee.return_value = {"id": 77}

    intent = ParsedIntent(
        task_type="create_employee",
        action="create",
        entities={"employee": {"first_name": "Ola", "last_name": "Nordmann"}},
        fields={"email": "ola@example.com", "phone": "+47 12345678"},
    )

    plan = {"search_strategy": {"skip_duplicate_check": True}}
    result = workflow.execute(intent, client, context={"plan": plan})
    assert result.success is True
    assert result.created_ids["employee_id"] == 77
    client.create_employee.assert_called_once()


def test_create_employee_existing():
    workflow = CreateEmployeeWorkflow()
    client = Mock()
    client.find_employee_by_email.return_value = {"id": 55, "email": "ola@example.com"}

    intent = ParsedIntent(
        task_type="create_employee",
        action="create",
        entities={"employee": {"first_name": "Ola", "last_name": "Nordmann"}},
        fields={"email": "ola@example.com"},
    )

    result = workflow.execute(intent, client, context={"plan": {}})
    assert result.success is True
    assert result.created_ids["employee_id"] == 55
    assert "already existed" in result.notes[0]


# --- Customer ---

def test_create_customer_new():
    workflow = CreateCustomerWorkflow()
    client = Mock()
    client.create_customer.return_value = {"id": 9}

    intent = ParsedIntent(
        task_type="create_customer",
        action="create",
        entities={"customer": {"name": "Nordic Bakery AS"}},
        fields={"email": "post@nordicbakery.no"},
    )

    plan = {"search_strategy": {"skip_duplicate_check": True}}
    result = workflow.execute(intent, client, context={"plan": plan})
    assert result.success is True
    assert result.created_ids["customer_id"] == 9


# --- Product ---

def test_create_product_new():
    workflow = CreateProductWorkflow()
    client = Mock()
    client.create_product.return_value = {"id": 22}

    intent = ParsedIntent(
        task_type="create_product",
        action="create",
        entities={"product": {"name": "Consulting Hour"}},
        fields={},
    )

    plan = {"search_strategy": {"skip_duplicate_check": True}}
    result = workflow.execute(intent, client, context={"plan": plan})
    assert result.success is True
    assert result.created_ids["product_id"] == 22


# --- Project ---

def test_create_project_with_customer():
    workflow = CreateProjectWorkflow()
    client = Mock()
    client.find_customer_by_name.return_value = {"id": 5, "name": "Nordic Bakery AS"}
    client.create_project.return_value = {"id": 101}

    intent = ParsedIntent(
        task_type="create_project",
        action="create",
        entities={"project": {"name": "Migration Project"}},
        fields={"customer_name": "Nordic Bakery AS"},
    )

    plan = {"search_strategy": {"lookup_customer": True}}
    result = workflow.execute(intent, client, context={"plan": plan})
    assert result.success is True
    assert result.created_ids["project_id"] == 101
    client.find_customer_by_name.assert_called_once_with("Nordic Bakery AS")


def test_create_project_without_customer():
    workflow = CreateProjectWorkflow()
    client = Mock()
    client.create_project.return_value = {"id": 102}

    intent = ParsedIntent(
        task_type="create_project",
        action="create",
        entities={"project": {"name": "Simple Project"}},
        fields={},
    )

    plan = {"search_strategy": {"lookup_customer": False}}
    result = workflow.execute(intent, client, context={"plan": plan})
    assert result.success is True
    assert result.created_ids["project_id"] == 102
    client.find_customer_by_name.assert_not_called()


# --- Invoice ---

def test_create_invoice_full_flow():
    workflow = CreateInvoiceWorkflow()
    client = Mock()

    client.find_customer_by_name.return_value = {"id": 10, "name": "Nordic Bakery AS"}
    client.find_product_by_name.return_value = {"id": 20, "name": "Consulting Hour"}
    client.post.side_effect = [
        {"id": 300},  # order creation
        {"id": 400},  # invoice creation
    ]

    intent = ParsedIntent(
        task_type="create_invoice",
        action="create",
        entities={
            "invoice": {
                "customer_name": "Nordic Bakery AS",
                "lines": [
                    {"product_name": "Consulting Hour", "quantity": 2, "unit_price": 1500},
                ],
            }
        },
        fields={"customer_name": "Nordic Bakery AS"},
    )

    from app.context import ExecutionContext
    ctx = ExecutionContext()
    result = workflow.execute(intent, client, context={"plan": {}, "execution_context": ctx})

    assert result.success is True
    assert result.created_ids["order_id"] == 300
    assert result.created_ids["invoice_id"] == 400
    assert client.find_customer_by_name.call_count == 1
    assert client.find_product_by_name.call_count == 1
    assert client.post.call_count == 2
