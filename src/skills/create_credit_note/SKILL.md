# create_credit_note
**Description:** Create a credit note to reverse or partially credit an invoice

## Fields to extract
- customer: Customer name (required)
- amount: Credit amount (optional, full credit if omitted)
- invoiceNumber: Invoice number to credit (optional)
- reason: Credit reason (optional)

## Steps

1. GET /customer?name={customerName}&fields=id,name
   — Resolve customer ID.

2. GET /invoice?customerId={customerId}&invoiceDateFrom={3yearsAgo}&invoiceDateTo={today}&count=50&fields=id,invoiceNumber,amount,amountOutstanding
   — Find the invoice to credit.

3. Try POST /invoice/{invoiceId}/:createCreditNote:
   ```json
   {
     "date": "{today}",
     "comment": "{reason or 'Credit note'}"
   }
   ```

4. If that returns 404/405, try POST /invoice/{invoiceId}/creditNote with same body.

5. If both fail, post a reversal voucher:
   POST /ledger/voucher with postings:
   - Debit 3000 (Sales Revenue): amount (reverses revenue)
   - Credit 1500 (Accounts Receivable): amount (reverses AR)

## Notes
- Credit notes reduce/reverse revenue and AR
- Always try API paths before falling back to voucher
- The voucher fallback uses accounts 3000 (debit) and 1500 (credit)
