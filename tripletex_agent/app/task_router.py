from app.schemas import ParsedIntent
from app.workflows.base import BaseWorkflow
from app.workflows.create_customer import CreateCustomerWorkflow
from app.workflows.create_employee import CreateEmployeeWorkflow
from app.workflows.create_invoice import CreateInvoiceWorkflow
from app.workflows.create_product import CreateProductWorkflow
from app.workflows.create_project import CreateProjectWorkflow
from app.workflows.delete_travel_expense import DeleteTravelExpenseWorkflow


class UnsupportedTaskError(Exception):
    pass


_WORKFLOW_MAP: dict[str, type[BaseWorkflow]] = {
    "create_employee": CreateEmployeeWorkflow,
    "create_customer": CreateCustomerWorkflow,
    "create_product": CreateProductWorkflow,
    "create_project": CreateProjectWorkflow,
    "create_invoice": CreateInvoiceWorkflow,
    "delete_travel_expense": DeleteTravelExpenseWorkflow,
}


def get_workflow(intent: ParsedIntent) -> BaseWorkflow:
    workflow_cls = _WORKFLOW_MAP.get(intent.task_type)
    if workflow_cls is None:
        raise UnsupportedTaskError(f"Unsupported task type: {intent.task_type}")
    return workflow_cls()
