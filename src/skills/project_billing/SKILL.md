# project_billing
**Description:** Bill a customer for project work: generate invoice from logged hours/costs (Tier 3)

## Fields to extract
- project: Project name (required)
- customer: Customer name (required)
- billingDate: Invoice date YYYY-MM-DD (default today)
- includeHours: Whether to include logged hours (default yes)
- fixedAmount: Fixed billing amount (optional, overrides hour calculation)

## Steps

1. GET /project?name={projectName}&fields=id,name,customer
   — Resolve project. Get linked customer.

2. GET /customer?name={customerName}&fields=id,name
   — Resolve or confirm customer ID.

3. GET /project/hour?projectId={projectId}&dateFrom={projectStart}&dateTo={today}&count=200&fields=id,hours,hourlyRate,employee
   — Get all logged hours for project.

4. Calculate total: sum(hours × hourlyRate) or use fixedAmount.

5. GET /project/orderLine or POST /order for billable hours:
   ```json
   {
     "customer": {"id": {customerId}},
     "orderDate": "{billingDate}",
     "orderLines": [
       {"description": "Project work: {projectName}", "unitPriceExcludingVatCurrency": {totalAmount}, "count": 1}
     ]
   }
   ```

6. POST /invoice:
   ```json
   {"order": {"id": {orderId}}, "invoiceDate": "{billingDate}", "sendToCustomer": false}
   ```

## Notes
- Tier 3 — up to 25 write calls
- If fixedAmount provided, use that instead of calculated hours × rate
- Note project ID in invoice description for tracking
