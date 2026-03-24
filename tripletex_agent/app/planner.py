from __future__ import annotations

from app.schemas import ParsedIntent


def build_execution_plan(intent: ParsedIntent) -> dict:
    """Build a lightweight execution plan from ParsedIntent.

    Returns a dict with task_type, required_dependencies, should_verify,
    assume_fresh_account, and search_strategy.
    """
    task_type = intent.task_type
    plan: dict = {
        "task_type": task_type,
        "required_dependencies": [],
        "should_verify": False,
        "assume_fresh_account": True,
        "search_strategy": {},
    }

    if task_type == "create_employee":
        plan["assume_fresh_account"] = True
        plan["should_verify"] = False
        plan["search_strategy"] = {"skip_duplicate_check": True}

    elif task_type == "create_customer":
        plan["assume_fresh_account"] = True
        plan["should_verify"] = False
        plan["search_strategy"] = {"skip_duplicate_check": True}

    elif task_type == "create_product":
        plan["assume_fresh_account"] = True
        plan["should_verify"] = False
        plan["search_strategy"] = {"skip_duplicate_check": True}

    elif task_type == "create_project":
        customer_name = intent.fields.get("customer_name")
        if customer_name:
            plan["required_dependencies"] = ["customer"]
            plan["search_strategy"] = {"lookup_customer": True}
        else:
            plan["search_strategy"] = {"lookup_customer": False}
        plan["should_verify"] = False

    elif task_type == "create_invoice":
        plan["required_dependencies"] = ["customer", "order"]
        plan["search_strategy"] = {
            "lookup_customer": True,
            "lookup_product": True,
        }
        plan["should_verify"] = False
        plan["assume_fresh_account"] = False

    elif task_type == "delete_travel_expense":
        plan["required_dependencies"] = ["travel_expense"]
        plan["search_strategy"] = {"lookup_travel_expense": True}
        plan["should_verify"] = False
        plan["assume_fresh_account"] = False

    elif task_type == "register_payment":
        plan["required_dependencies"] = ["invoice"]
        plan["search_strategy"] = {"lookup_invoice": True}
        plan["should_verify"] = False
        plan["assume_fresh_account"] = False

    elif task_type == "create_department":
        plan["assume_fresh_account"] = True
        plan["should_verify"] = False
        plan["search_strategy"] = {"skip_duplicate_check": True}

    return plan
