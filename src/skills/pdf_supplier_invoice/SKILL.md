# pdf_supplier_invoice
**Description:** Extract data from a PDF supplier invoice and book it in Tripletex

## Fields to extract (from PDF)
- supplier: Supplier name from PDF header
- organizationNumber: Supplier org number from PDF
- amount: Total amount incl. VAT
- invoiceDate: Invoice date on PDF
- dueDate: Due date on PDF
- invoiceNumber: Supplier's invoice number
- description: What was purchased

## Steps

1. Parse the attached PDF file to extract all fields above.
   Key patterns to look for:
   - "Org.nr" / "Organisasjonsnummer" → org number
   - "Fakturadato" / "Invoice date" → date
   - "Forfallsdato" / "Due date" → due date
   - "Total" / "Sum inkl. mva" → total amount
   - "Fakturanr" / "Invoice no" → invoice number

2. GET /supplier?name={supplierName}&fields=id,name
   — Find existing supplier.

3. If not found by name, try:
   GET /supplier?organizationNumber={orgNumber}&fields=id,name

4. If still not found, POST /supplier:
   ```json
   {"name": "{supplierName}", "organizationNumber": "{orgNumber}", "isSupplier": true}
   ```

5. GET /ledger/account?number=6590&fields=id,number
   — Expense account ID.

6. GET /ledger/account?number=2400&fields=id,number
   — AP account ID.

7. POST /ledger/voucher:
   - Debit 6590 (expense): amount
   - Credit 2400 (AP): amount
   - date: invoiceDate, description: "{supplierName} - Invoice {invoiceNumber}"

## Notes
- PDF text is already extracted and available in the prompt as [filename.pdf]
- row must start at 1 in postings array
