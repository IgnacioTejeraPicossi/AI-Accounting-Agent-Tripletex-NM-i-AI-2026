# create_supplier
**Description:** Register a new supplier or vendor in Tripletex

## Fields to extract
- name: Supplier company name (required)
- organizationNumber: Org number (optional)
- email: Contact email (optional)
- phoneNumber: Phone (optional)
- bankAccountNumber: IBAN or account number (optional)

## Steps

1. GET /supplier?name={name}&fields=id,name,organizationNumber
   — Search for existing supplier.

2. If organizationNumber provided:
   GET /supplier?organizationNumber={orgNumber}&fields=id,name
   — Also check by org number.

3. If not found, POST /supplier with:
   ```json
   {
     "name": "{name}",
     "organizationNumber": "{orgNumber or omit}",
     "email": "{email or omit}",
     "phoneNumber": "{phone or omit}",
     "isSupplier": true
   }
   ```

4. If bankAccountNumber provided, after creating supplier:
   GET /supplier/{supplierId} to verify creation.

## Notes
- isSupplier: true is required
- Do NOT use /customer endpoint for suppliers; use /supplier
- organizationNumber as string, no spaces
