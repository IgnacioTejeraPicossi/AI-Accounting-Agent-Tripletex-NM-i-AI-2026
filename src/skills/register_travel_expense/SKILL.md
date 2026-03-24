# register_travel_expense
**Description:** Register a travel expense report for an employee

## Fields to extract
- employee: Employee name (required)
- description: Purpose of travel (required)
- travelDate: Date of travel YYYY-MM-DD (required)
- amount: Total expense amount (required)
- costType: Type of cost (transport, hotel, meals, etc.)
- project: Project name (optional)

## Steps

1. GET /employee?firstName={firstName}&lastName={lastName}&fields=id,firstName,lastName
   — Resolve employee ID.

2. If project mentioned:
   GET /project?name={projectName}&fields=id,name
   — Resolve project ID.

3. POST /travel/expense with:
   ```json
   {
     "employee": {"id": {employeeId}},
     "description": "{description}",
     "travelDetails": {
       "departureDate": "{travelDate}",
       "returnDate": "{travelDate}"
     },
     "isCompleted": false
   }
   ```

4. POST /travel/expense/cost with:
   ```json
   {
     "travelExpense": {"id": {expenseId}},
     "costType": {"id": 1},
     "amount": {amount},
     "description": "{costType description}"
   }
   ```

## Notes
- Use costType not perDiem for expense lines
- isCompleted: false allows the expense to be edited
- If project given, add "project": {"id": projectId} to the expense body
