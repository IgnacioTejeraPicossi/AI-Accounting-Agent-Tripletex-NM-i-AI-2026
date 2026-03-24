# register_payment
**Description:** Register payment for an existing unpaid invoice

## Fields to extract
- customer: Customer name (to find invoice)
- amount: Payment amount
- invoiceNumber: Invoice number (optional, helps find exact invoice)
- paymentDate: YYYY-MM-DD (default today)

## Steps

1. GET /customer?name={customerName}&fields=id,name
   — Resolve customer ID.

2. GET /invoice?customerId={customerId}&invoiceDateFrom={3yearsAgo}&invoiceDateTo={today}&count=50&fields=id,invoiceNumber,amount,amountOutstanding
   — Find unpaid invoices for this customer.

3. Select invoice: match by invoiceNumber if provided, otherwise pick the one where
   amountOutstanding ≈ payment amount.

4. POST /invoice/{invoiceId}/:payment:
   ```json
   {
     "paymentDate": "{paymentDate}",
     "paidAmount": {amount},
     "paymentTypeId": 1
   }
   ```

5. If :payment returns 404/405, try POST /invoice/{invoiceId}/:createPayment with same body.

6. If both fail, post a manual voucher:
   POST /ledger/voucher:
   - Debit 1920 (Bank account): amount
   - Credit 1500 (Accounts Receivable): amount

## Notes
- amountOutstanding is the remaining unpaid amount
- paymentTypeId: 1 is standard bank
- The 3-years-ago date: use today minus 1095 days
