from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient, TripletexValidationError
from app.workflows.base import BaseWorkflow


class CreateCustomerWorkflow(BaseWorkflow):
    name = "create_customer"

    def validate_intent(self, intent: ParsedIntent) -> None:
        customer = intent.entities.get("customer", {})
        if not customer.get("name"):
            raise TripletexValidationError("Customer name is required")

    def execute(self, intent: ParsedIntent, client: TripletexClient, context: dict) -> ExecutionResult:
        self.validate_intent(intent)

        plan = context.get("plan", {})
        customer_name = intent.entities["customer"]["name"]
        email = intent.fields.get("email")

        skip_dup = plan.get("search_strategy", {}).get("skip_duplicate_check", False)

        if not skip_dup:
            existing = client.find_customer_by_name(customer_name)
            if existing:
                return ExecutionResult(
                    success=True,
                    workflow_name=self.name,
                    created_ids={"customer_id": existing.get("id")},
                    notes=["Customer already existed; skipped duplicate creation"],
                    verification={"existing": True, "skipped_get_verify": True},
                )

        created = client.create_customer(name=customer_name, email=email)

        return ExecutionResult(
            success=True,
            workflow_name=self.name,
            created_ids={"customer_id": created.get("id")},
            notes=[],
            verification={"skipped_get_verify": True},
        )

    def verify(self, intent: ParsedIntent, client: TripletexClient, execution_result: ExecutionResult) -> dict:
        return execution_result.verification
