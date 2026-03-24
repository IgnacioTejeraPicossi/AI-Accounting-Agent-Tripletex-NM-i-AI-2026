# overdue_invoice_reminder
**Description:** Find overdue invoices and register reminder fees (Tier 3)

## Fields to extract
- customer: Customer name (optional, if targeting specific customer)
- reminderFee: Fee amount to add (default 70 NOK per Norwegian law)
- daysOverdue: Minimum days past due (default 14)

## Steps

1. GET /invoice?invoiceDateFrom={90daysAgo}&invoiceDateTo={today}&count=100&fields=id,invoiceNumber,customerId,amount,amountOutstanding,dueDate
   — Get invoices from last 90 days. Filter for overdue ones (dueDate < today AND amountOutstanding > 0).

2. If customer specified:
   GET /customer?name={customerName}&fields=id,name
   Filter invoices by customerId.

3. For each overdue invoice:
   a. Calculate days overdue: today - dueDate
   b. If days >= daysOverdue, add reminder fee:

4. POST /reminder with:
   ```json
   {
     "invoice": {"id": {invoiceId}},
     "reminderDate": "{today}",
     "fee": {reminderFee},
     "interest": 0
   }
   ```
   Or if /reminder not available: POST /invoice/{invoiceId}/reminder

5. If reminder endpoint unavailable (404/405), add fee as new invoice line:
   POST /order then POST /invoice for reminder fee amount.

## Notes
- Tier 3 — up to 25 write calls
- Norwegian standard reminder fee: 70 NOK
- Only apply reminder once per invoice (check if already has reminder)
- daysOverdue check: (today - dueDate).days >= 14
