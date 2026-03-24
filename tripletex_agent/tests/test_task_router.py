import pytest

from app.schemas import ParsedIntent
from app.task_router import UnsupportedTaskError, get_workflow


def test_route_employee():
    intent = ParsedIntent(task_type="create_employee", action="create")
    workflow = get_workflow(intent)
    assert workflow.name == "create_employee"


def test_route_customer():
    intent = ParsedIntent(task_type="create_customer", action="create")
    workflow = get_workflow(intent)
    assert workflow.name == "create_customer"


def test_route_product():
    intent = ParsedIntent(task_type="create_product", action="create")
    workflow = get_workflow(intent)
    assert workflow.name == "create_product"


def test_route_project():
    intent = ParsedIntent(task_type="create_project", action="create")
    workflow = get_workflow(intent)
    assert workflow.name == "create_project"


def test_route_invoice():
    intent = ParsedIntent(task_type="create_invoice", action="create")
    workflow = get_workflow(intent)
    assert workflow.name == "create_invoice"


def test_route_delete_travel_expense():
    intent = ParsedIntent(task_type="delete_travel_expense", action="delete")
    workflow = get_workflow(intent)
    assert workflow.name == "delete_travel_expense"


def test_route_unsupported():
    intent = ParsedIntent(task_type="unsupported", action="unknown")
    with pytest.raises(UnsupportedTaskError):
        get_workflow(intent)
