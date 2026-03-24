# reverse_payment
**Description:** Reverse or cancel a previously registered payment

## Fields to extract (testing)
- customer: Customer name (to find invoice/payment)
- amount: Payment amount to reverse
- paymentDate: Original payment date
- invoiceNumber: Invoice number (optional)

## Steps

1. GET /customer?name={customerName}&fields=id,name
   — Resolve customer ID.

2. GET /invoice?customerId={customerId}&invoiceDateFrom={3yearsAgo}&invoiceDateTo={today}&count=50&fields=id,invoiceNumber,amount,amountOutstanding
   — Find the invoice.

3. Try POST /invoice/{invoiceId}/:reversePayment or DELETE on the payment.

4. If not available, post a counter-entry voucher:
   POST /ledger/voucher:
   - Debit 1500 (Accounts Receivable): amount  ← reverses the original credit
   - Credit 1920 (Bank): amount                ← reverses the original debit

## Notes
- This is the exact opposite of register_payment
- Debit AR (1500), Credit Bank (1920) to undo a payment
- Row starts at 1
