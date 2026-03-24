# create_project
**Description:** Create a new project in Tripletex, optionally linked to a customer

## Fields to extract
- name: Project name (required)
- number: Project number (optional)
- startDate: Start date YYYY-MM-DD (required)
- endDate: End date YYYY-MM-DD (optional)
- customer: Customer name or org number (optional)
- projectManager: Employee name (optional)

## Steps

1. GET /project?name={name}&fields=id,name,number
   — Check for existing project.

2. If customer mentioned:
   GET /customer?name={customerName}&fields=id,name
   — Resolve customer ID.

3. If projectManager mentioned:
   GET /employee?firstName={firstName}&lastName={lastName}&fields=id,firstName,lastName
   — Resolve project manager employee ID.

4. GET /employee?fields=id,companyId&count=1
   — Get companyId.

5. POST /project with:
   ```json
   {
     "name": "{name}",
     "number": "{number or omit}",
     "startDate": "{startDate}",
     "endDate": "{endDate or omit}",
     "customer": {"id": {customerId}},
     "projectManager": {"id": {managerId}},
     "isInternal": false
   }
   ```

## Notes
- startDate is required; use today if not specified
- customer and projectManager are optional — omit if not provided
- isInternal: false for customer-facing projects
