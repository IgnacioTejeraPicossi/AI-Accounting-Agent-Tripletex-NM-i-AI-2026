from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient, TripletexValidationError
from app.workflows.base import BaseWorkflow


class CreateEmployeeWorkflow(BaseWorkflow):
    name = "create_employee"

    def validate_intent(self, intent: ParsedIntent) -> None:
        employee = intent.entities.get("employee", {})
        first_name = employee.get("first_name")
        last_name = employee.get("last_name")
        if not first_name or not last_name:
            raise TripletexValidationError("Employee first_name and last_name are required")

    def execute(
        self,
        intent: ParsedIntent,
        client: TripletexClient,
        context: dict,
    ) -> ExecutionResult:
        self.validate_intent(intent)

        plan = context.get("plan", {})
        employee = intent.entities["employee"]
        email = intent.fields.get("email")
        phone = intent.fields.get("phone")

        skip_dup = plan.get("search_strategy", {}).get("skip_duplicate_check", False)

        if email and not skip_dup:
            existing = client.find_employee_by_email(email)
            if existing:
                return ExecutionResult(
                    success=True,
                    workflow_name=self.name,
                    created_ids={"employee_id": existing.get("id")},
                    notes=["Employee already existed; skipped duplicate creation"],
                    verification={"existing": True, "skipped_get_verify": True},
                )

        created = client.create_employee(
            first_name=employee["first_name"],
            last_name=employee["last_name"],
            email=email,
            mobile_number=phone,
        )

        return ExecutionResult(
            success=True,
            workflow_name=self.name,
            created_ids={"employee_id": created.get("id")},
            notes=[],
            verification={"skipped_get_verify": True},
        )

    def verify(
        self,
        intent: ParsedIntent,
        client: TripletexClient,
        execution_result: ExecutionResult,
    ) -> dict:
        return execution_result.verification
