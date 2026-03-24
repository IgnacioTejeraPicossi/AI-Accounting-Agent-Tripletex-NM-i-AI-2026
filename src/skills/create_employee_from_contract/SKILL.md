# create_employee_from_contract
**Description:** Extract employee data from a contract PDF and create the employee record

## Fields to extract (from PDF contract)
- firstName / lastName: Employee full name
- email: Email in contract
- startDate: Employment start date
- salary: Annual salary amount
- position / title: Job title
- department: Department name

## Steps

1. Parse the attached PDF for employee data:
   - Look for: "Navn" / "Name", "E-post" / "Email", "Startdato" / "Start date"
   - Look for: "Lønn" / "Salary", "Stilling" / "Position"

2. GET /employee?firstName={firstName}&lastName={lastName}&fields=id,firstName,lastName
   — Check if employee exists.

3. If department mentioned:
   GET /department?name={deptName}&fields=id,name
   — Resolve or create department.

4. If employee not found, POST /employee:
   ```json
   {
     "firstName": "{firstName}",
     "lastName": "{lastName}",
     "email": "{email or generated}",
     "startDate": "{startDate}",
     "userType": "STANDARD"
   }
   ```

5. If salary mentioned, POST /salary/transaction or note it (salary setup varies by setup).

## Notes
- If email not found in PDF, generate: firstname.lastname@company.no
- userType must be "STANDARD"
- PDF text is available in the prompt as [filename.pdf]
- Parse carefully: names may appear near "Arbeidstaker" (employee) label
