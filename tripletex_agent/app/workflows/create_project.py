from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient, TripletexNotFoundError, TripletexValidationError
from app.workflows.base import BaseWorkflow


class CreateProjectWorkflow(BaseWorkflow):
    name = "create_project"

    def validate_intent(self, intent: ParsedIntent) -> None:
        project = intent.entities.get("project", {})
        if not str(project.get("name", "")).strip():
            raise TripletexValidationError("Project name is required")

    def execute(self, intent: ParsedIntent, client: TripletexClient, context: dict) -> ExecutionResult:
        self.validate_intent(intent)

        plan = context.get("plan", {})
        project = intent.entities.get("project", {})

        project_name = str(project.get("name", "")).strip()
        customer_name = intent.fields.get("customer_name")
        description = intent.fields.get("description")
        start_date = intent.fields.get("start_date")
        end_date = intent.fields.get("end_date")

        customer_id = None
        if plan.get("search_strategy", {}).get("lookup_customer") and customer_name:
            customer = client.find_customer_by_name(customer_name)
            if not customer:
                raise TripletexNotFoundError(f"Customer not found for project: {customer_name}")
            customer_id = customer["id"]

        created = client.create_project(
            name=project_name,
            customer_id=customer_id,
            description=description,
            start_date=start_date,
            end_date=end_date,
        )

        return ExecutionResult(
            success=True,
            workflow_name=self.name,
            created_ids={"project_id": created.get("id")},
            notes=[],
            verification={"skipped_get_verify": True},
        )

    def verify(self, intent: ParsedIntent, client: TripletexClient, execution_result: ExecutionResult) -> dict:
        return execution_result.verification
