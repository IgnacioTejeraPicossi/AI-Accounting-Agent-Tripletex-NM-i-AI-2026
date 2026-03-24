from datetime import date

from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient, TripletexNotFoundError, TripletexValidationError
from app.workflows.base import BaseWorkflow


class CreateInvoiceWorkflow(BaseWorkflow):
    name = "create_invoice"

    def validate_intent(self, intent: ParsedIntent) -> None:
        invoice = intent.entities.get("invoice", {})
        customer_name = invoice.get("customer_name") or intent.fields.get("customer_name")
        lines = invoice.get("lines", [])
        if not str(customer_name or "").strip():
            raise TripletexValidationError("Invoice customer_name is required")
        if not isinstance(lines, list) or not lines:
            raise TripletexValidationError("At least one invoice line is required")

    def execute(self, intent: ParsedIntent, client: TripletexClient, context: dict) -> ExecutionResult:
        self.validate_intent(intent)

        invoice = intent.entities.get("invoice", {})
        customer_name = invoice.get("customer_name") or intent.fields.get("customer_name")
        lines = invoice.get("lines", [])
        invoice_date = invoice.get("invoice_date") or intent.fields.get("invoice_date") or str(date.today())
        due_date = invoice.get("due_date") or intent.fields.get("due_date") or invoice_date

        # Step 1: Resolve customer
        customer = client.find_customer_by_name(customer_name)
        if not customer:
            raise TripletexNotFoundError(f"Customer not found for invoice: {customer_name}")
        customer_id = customer["id"]

        # Step 2: Build order lines (resolve products if needed)
        order_lines = [self._build_order_line(line, client) for line in lines]

        # Step 3: Create order
        order_payload = {
            "customer": {"id": customer_id},
            "orderLines": order_lines,
        }
        created_order = client.post("/order", json_body=order_payload)
        order_id = created_order.get("id")
        if not order_id:
            raise TripletexValidationError("Order creation did not return an id")

        # Step 4: Create invoice from order
        invoice_payload = {
            "invoiceDate": invoice_date,
            "invoiceDueDate": due_date,
            "customer": {"id": customer_id},
            "orders": [{"id": order_id}],
        }
        created_invoice = client.post("/invoice", json_body=invoice_payload)

        exec_ctx = context.get("execution_context")
        if exec_ctx:
            exec_ctx.invoice_order_flow_used = True

        return ExecutionResult(
            success=True,
            workflow_name=self.name,
            created_ids={
                "order_id": order_id,
                "invoice_id": created_invoice.get("id"),
            },
            notes=[],
            verification={"skipped_get_verify": True},
        )

    def verify(self, intent: ParsedIntent, client: TripletexClient, execution_result: ExecutionResult) -> dict:
        return execution_result.verification

    def _build_order_line(self, raw_line: dict, client: TripletexClient) -> dict:
        if not isinstance(raw_line, dict):
            raise TripletexValidationError("Invoice line must be an object")

        quantity = raw_line.get("quantity", 1)
        unit_price = raw_line.get("unit_price")
        product_name = raw_line.get("product_name")
        description = raw_line.get("description")

        try:
            quantity = int(quantity)
        except (TypeError, ValueError):
            raise TripletexValidationError(f"Invalid quantity: {quantity}")

        if unit_price is not None:
            try:
                unit_price = float(unit_price)
            except (TypeError, ValueError):
                raise TripletexValidationError(f"Invalid unit_price: {unit_price}")

        line: dict = {"count": quantity}

        if unit_price is not None:
            line["unitPrice"] = unit_price

        if product_name:
            product = client.find_product_by_name(product_name)
            if not product:
                raise TripletexNotFoundError(f"Product not found: {product_name}")
            line["product"] = {"id": product["id"]}

        if description:
            line["description"] = description
        elif product_name:
            line["description"] = product_name

        return line
