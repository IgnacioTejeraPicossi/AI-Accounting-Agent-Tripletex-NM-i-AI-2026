# create_customer
**Description:** Create a new customer or client in Tripletex

## Fields to extract
- name: Company or person name (required)
- organizationNumber: Norwegian 9-digit org number (optional)
- email: Contact email (optional)
- phoneNumber: Contact phone (optional)

## Steps

1. GET /customer?name={name}&fields=id,name,organizationNumber
   — Search by name to avoid duplicates. If found, use existing ID.

2. If organizationNumber provided, also try:
   GET /customer?organizationNumber={orgNumber}&fields=id,name
   — If found, use existing ID.

3. If not found, POST /customer with:
   ```json
   {
     "name": "{name}",
     "organizationNumber": "{orgNumber or omit}",
     "email": "{email or omit}",
     "phoneNumber": "{phone or omit}",
     "isCustomer": true
   }
   ```

4. Log the returned customer ID.

## Notes
- organizationNumber must be a string, no spaces or dashes
- isCustomer: true is required for invoicing
- The response wraps in {"value": {...}} — the registry unwraps it automatically
