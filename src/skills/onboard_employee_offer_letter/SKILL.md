# onboard_employee_offer_letter
**Description:** Onboard a new employee from an offer letter PDF: create employee, set department, salary (Tier 3)

## Fields to extract (from offer letter PDF)
- firstName / lastName: Employee name
- email: Work email
- startDate: Start date
- salary: Annual salary
- position: Job title
- department: Department name

## Steps

1. Parse attached offer letter PDF for all fields above.
   Look for: "Tilbudsbrev" / "Offer letter", "Ansettelsesdato", "Grunnlønn"

2. GET /department?name={deptName}&fields=id,name
   — Find department. Create if not found: POST /department {"name": "{deptName}"}

3. GET /employee?firstName={firstName}&lastName={lastName}&fields=id
   — Check if employee exists.

4. If not found, POST /employee:
   ```json
   {
     "firstName": "{firstName}",
     "lastName": "{lastName}",
     "email": "{email or generated}",
     "startDate": "{startDate}",
     "userType": "STANDARD",
     "department": {"id": {deptId}}
   }
   ```

5. If salary in offer letter, POST /salary/transaction:
   ```json
   {"employee": {"id": {employeeId}}, "type": {"id": 1}, "amount": {monthlySalary}}
   ```
   Note: monthlySalary = annualSalary / 12

## Notes
- Tier 3 — up to 25 write calls
- PDF text available as [filename.pdf] in prompt
- If salary endpoint unavailable, record employee creation only
- generated email: firstname.lastname@company.no
