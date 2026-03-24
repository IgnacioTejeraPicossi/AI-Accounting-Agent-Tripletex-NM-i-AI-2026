# receipt_expense
**Description:** Book an expense with a receipt, linked to a department or project

## Fields to extract
- employee: Employee name (required)
- amount: Expense amount (required)
- description: What was purchased (required)
- expenseDate: Date YYYY-MM-DD (default today)
- department: Department name (optional)
- project: Project name (optional)
- account: Expense account number (default 6800 for general expenses)

## Steps

1. GET /employee?firstName={firstName}&lastName={lastName}&fields=id,firstName,lastName
   — Resolve employee ID.

2. If department mentioned:
   GET /department?name={deptName}&fields=id,name
   — Resolve department ID. Create if not found (POST /department).

3. If project mentioned:
   GET /project?name={projectName}&fields=id,name
   — Resolve project ID.

4. GET /ledger/account?number={accountNumber}&fields=id,number,name
   — Resolve expense account ID (default 6800).

5. GET /ledger/account?number=1920&fields=id,number
   — Resolve bank account ID.

6. POST /ledger/voucher:
   ```json
   {
     "description": "{description}",
     "date": "{expenseDate}",
     "postings": [
       {
         "account": {"id": {expenseAccountId}},
         "department": {"id": {deptId or omit}},
         "project": {"id": {projectId or omit}},
         "debitAmount": {amount},
         "creditAmount": 0,
         "amountGross": {amount},
         "row": 1,
         "description": "{description}"
       },
       {
         "account": {"id": {bankAccountId}},
         "creditAmount": {amount},
         "debitAmount": 0,
         "amountGross": {amount},
         "row": 2,
         "description": "{description}"
       }
     ]
   }
   ```

## Notes
- row starts at 1 (not 0)
- department and project are optional in postings
