from app.planner import build_execution_plan
from app.schemas import ParsedIntent


def test_plan_create_employee():
    intent = ParsedIntent(task_type="create_employee", action="create")
    plan = build_execution_plan(intent)
    assert plan["assume_fresh_account"] is True
    assert plan["should_verify"] is False
    assert plan["search_strategy"].get("skip_duplicate_check") is True


def test_plan_create_customer():
    intent = ParsedIntent(task_type="create_customer", action="create")
    plan = build_execution_plan(intent)
    assert plan["assume_fresh_account"] is True
    assert plan["should_verify"] is False


def test_plan_create_project_with_customer():
    intent = ParsedIntent(
        task_type="create_project",
        action="create",
        fields={"customer_name": "Nordic Bakery AS"},
    )
    plan = build_execution_plan(intent)
    assert plan["search_strategy"]["lookup_customer"] is True
    assert "customer" in plan["required_dependencies"]


def test_plan_create_project_without_customer():
    intent = ParsedIntent(task_type="create_project", action="create")
    plan = build_execution_plan(intent)
    assert plan["search_strategy"]["lookup_customer"] is False


def test_plan_create_invoice():
    intent = ParsedIntent(task_type="create_invoice", action="create")
    plan = build_execution_plan(intent)
    assert plan["search_strategy"]["lookup_customer"] is True
    assert plan["search_strategy"]["lookup_product"] is True
    assert plan["should_verify"] is False
    assert "customer" in plan["required_dependencies"]
    assert "order" in plan["required_dependencies"]
