from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient, TripletexValidationError
from app.workflows.base import BaseWorkflow


class CreateProductWorkflow(BaseWorkflow):
    name = "create_product"

    def validate_intent(self, intent: ParsedIntent) -> None:
        product = intent.entities.get("product", {})
        if not product.get("name"):
            raise TripletexValidationError("Product name is required")

    def execute(self, intent: ParsedIntent, client: TripletexClient, context: dict) -> ExecutionResult:
        self.validate_intent(intent)

        plan = context.get("plan", {})
        product_name = intent.entities["product"]["name"]

        skip_dup = plan.get("search_strategy", {}).get("skip_duplicate_check", False)

        if not skip_dup:
            existing = client.find_product_by_name(product_name)
            if existing:
                return ExecutionResult(
                    success=True,
                    workflow_name=self.name,
                    created_ids={"product_id": existing.get("id")},
                    notes=["Product already existed; skipped duplicate creation"],
                    verification={"existing": True, "skipped_get_verify": True},
                )

        created = client.create_product(name=product_name)

        return ExecutionResult(
            success=True,
            workflow_name=self.name,
            created_ids={"product_id": created.get("id")},
            notes=[],
            verification={"skipped_get_verify": True},
        )

    def verify(self, intent: ParsedIntent, client: TripletexClient, execution_result: ExecutionResult) -> dict:
        return execution_result.verification
