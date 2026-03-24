# create_employee
**Description:** Create a new employee record in Tripletex

## Fields to extract
- firstName: First name (required)
- lastName: Last name (required)
- email: Work email (optional, generate fake if missing: firstname.lastname@company.no)
- employeeNumber: Optional numeric ID
- startDate: Employment start date (YYYY-MM-DD, default today)
- salary: Annual salary amount (optional)

## Steps

1. GET /employee?firstName={firstName}&lastName={lastName}&fields=id,firstName,lastName
   — Check if employee already exists.

2. GET /employee?fields=id,companyId&count=1
   — Get companyId from first employee record.

3. If employee not found, POST /employee with:
   ```json
   {
     "firstName": "{firstName}",
     "lastName": "{lastName}",
     "email": "{email or generated}",
     "employeeNumber": "{employeeNumber or omit}",
     "startDate": "{startDate}",
     "userType": "STANDARD"
   }
   ```

4. Note returned employee ID.

## Notes
- userType: "STANDARD" is required — do NOT use "SYSTEM" or "ADMINISTRATOR"
- If no email in prompt, generate: firstname.lastname@company.no (lowercase, no spaces)
- employeeNumber: if not specified, omit the field entirely (Tripletex auto-assigns)
- startDate defaults to today if not provided
