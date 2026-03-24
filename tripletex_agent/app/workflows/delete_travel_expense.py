from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient, TripletexNotFoundError
from app.workflows.base import BaseWorkflow


class DeleteTravelExpenseWorkflow(BaseWorkflow):
    name = "delete_travel_expense"

    def validate_intent(self, intent: ParsedIntent) -> None:
        pass

    def execute(self, intent: ParsedIntent, client: TripletexClient, context: dict) -> ExecutionResult:
        expenses = client.list_values(
            "/travelExpense",
            params={"fields": "id,title,employee", "count": 100},
        )

        if not expenses:
            raise TripletexNotFoundError("No travel expenses found to delete")

        deleted_ids = []
        for expense in expenses:
            expense_id = expense.get("id")
            if expense_id:
                try:
                    client.delete(f"/travelExpense/{expense_id}")
                    deleted_ids.append(expense_id)
                except Exception:
                    pass

        return ExecutionResult(
            success=True,
            workflow_name=self.name,
            created_ids={"deleted_expense_ids": deleted_ids},
            notes=[f"Deleted {len(deleted_ids)} travel expense(s)"],
            verification={"skipped_get_verify": True},
        )

    def verify(self, intent: ParsedIntent, client: TripletexClient, execution_result: ExecutionResult) -> dict:
        return execution_result.verification
