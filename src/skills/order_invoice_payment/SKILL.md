# order_invoice_payment
**Description:** Full workflow: create order, convert to invoice, register payment

## Fields to extract
- customer: Customer name or org number (required)
- amount: Total amount (required)
- description: Order/invoice line description
- invoiceDate: YYYY-MM-DD (default today)
- paymentDate: YYYY-MM-DD (default today)

## Steps

1. GET /customer?name={customerName}&fields=id,name
   — Resolve customer ID.

2. POST /order:
   ```json
   {
     "customer": {"id": {customerId}},
     "orderDate": "{invoiceDate}",
     "deliveryDate": "{invoiceDate}",
     "orderLines": [
       {
         "description": "{description}",
         "unitPriceExcludingVatCurrency": {amountExclVat},
         "count": 1
       }
     ]
   }
   ```

3. POST /invoice:
   ```json
   {
     "order": {"id": {orderId}},
     "invoiceDate": "{invoiceDate}",
     "sendToCustomer": false
   }
   ```

4. POST /invoice/{invoiceId}/:payment or POST /invoice/{invoiceId}/:createPayment:
   ```json
   {
     "paymentDate": "{paymentDate}",
     "paidAmount": {totalAmountInclVat},
     "paymentTypeId": 1
   }
   ```

5. If payment endpoint returns 404/405, fall back to voucher:
   POST /ledger/voucher:
   - Debit 1920 (Bank): amount
   - Credit 1500 (Accounts Receivable): amount

## Notes
- Step 4 tries :payment first, then :createPayment if that fails
- paidAmount should include VAT (multiply excl. amount × 1.25 for 25% VAT)
- paymentTypeId: 1 = standard bank payment
