# register_supplier_invoice
**Description:** Book an incoming supplier invoice as a ledger voucher

## Fields to extract
- supplier: Supplier name or org number (required)
- amount: Invoice amount incl. VAT (required)
- invoiceDate: Invoice date YYYY-MM-DD (required)
- dueDate: Payment due date YYYY-MM-DD (optional)
- description: Invoice description / what was purchased
- accountNumber: Expense account (default 6590)

## Steps

1. GET /supplier?name={supplierName}&fields=id,name
   — Resolve supplier ID. Create supplier if not found (see create_supplier steps).

2. GET /ledger/account?number={accountNumber}&fields=id,number,name
   — Look up the expense account ID (e.g. 6590 for supplier expenses).

3. GET /ledger/account?number=2400&fields=id,number,name
   — Look up Accounts Payable account ID (2400).

4. POST /ledger/voucher with:
   ```json
   {
     "description": "{description}",
     "date": "{invoiceDate}",
     "postings": [
       {
         "account": {"id": {expenseAccountId}},
         "amountGross": {amount},
         "debitAmount": {amount},
         "creditAmount": 0,
         "row": 1,
         "description": "{description}"
       },
       {
         "account": {"id": {apAccountId}},
         "amountGross": {amount},
         "debitAmount": 0,
         "creditAmount": {amount},
         "row": 2,
         "description": "{description}"
       }
     ]
   }
   ```

## Notes
- row must start at 1 (not 0)
- Debit expense account (6590), Credit AP (2400) = standard supplier invoice posting
- amountGross = total amount incl. VAT
