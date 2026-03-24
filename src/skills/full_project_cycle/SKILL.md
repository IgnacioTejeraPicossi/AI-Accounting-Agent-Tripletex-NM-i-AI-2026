# full_project_cycle
**Description:** Complete project lifecycle: create project, log hours, add costs, invoice customer (Tier 3)

## Fields to extract
- projectName: Project name (required)
- customer: Customer name (required)
- employee: Employee doing the work
- hours: Number of hours to log
- hourlyRate: Rate per hour
- expenses[]: Additional project expenses
- invoiceDate: When to invoice

## Steps

1. GET /customer?name={customerName}&fields=id,name
   — Resolve customer. Create if not found.

2. GET /project?name={projectName}&fields=id,name
   — Check for existing project.

3. If not found, POST /project:
   ```json
   {"name": "{projectName}", "customer": {"id": {customerId}}, "startDate": "{today}", "isInternal": false}
   ```

4. GET /employee?firstName={firstName}&lastName={lastName}&fields=id
   — Resolve employee.

5. If hours to log, POST /project/hour:
   ```json
   {"project": {"id": {projectId}}, "employee": {"id": {employeeId}}, "date": "{today}", "hours": {hours}, "hourlyRate": {hourlyRate}}
   ```

6. For each additional expense, POST /ledger/voucher (debit expense / credit bank).

7. POST /order then POST /invoice to bill the customer for total project value.

## Notes
- Tier 3 — up to 25 write calls
- Total invoice amount = hours × hourlyRate + sum(expenses)
- Create order with total amount, convert to invoice
