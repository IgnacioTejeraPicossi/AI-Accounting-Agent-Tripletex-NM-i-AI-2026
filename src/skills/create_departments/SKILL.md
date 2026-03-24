# create_departments
**Description:** Create one or more departments in Tripletex

## Fields to extract
- name: Department name (required)
- departmentNumber: Optional numeric ID
- manager: Employee name for department manager (optional)

## Steps

1. GET /department?name={name}&fields=id,name
   — Check if department already exists.

2. If manager mentioned:
   GET /employee?firstName={firstName}&lastName={lastName}&fields=id,firstName,lastName
   — Resolve manager employee ID.

3. If not found, POST /department with:
   ```json
   {
     "name": "{name}",
     "departmentNumber": "{number or omit}",
     "departmentManager": {"id": {managerId or omit}}
   }
   ```

4. If multiple departments requested, repeat steps 1-3 for each.

## Notes
- If creating multiple departments from a list, loop through each name
- departmentNumber is optional; omit if not specified
- departmentManager is optional; omit if no manager named
