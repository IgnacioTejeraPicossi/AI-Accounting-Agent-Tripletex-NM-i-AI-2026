# create_invoice
**Description:** Create and send an invoice to a customer in Tripletex

## Fields to extract
- customer: Customer name or org number (required)
- amount: Invoice amount incl. or excl. VAT
- invoiceDate: Invoice date YYYY-MM-DD (default today)
- dueDate: Due date (default invoiceDate + 14 days)
- description: Invoice line description
- product: Product name (optional)

## Steps

1. GET /customer?name={customerName}&fields=id,name
   — Find or verify customer. If not found, create via create_customer skill logic.

2. GET /product?name={productName}&fields=id,name,priceExcludingVatCurrency
   — Find product if mentioned. Otherwise use description as order line.

3. POST /order with:
   ```json
   {
     "customer": {"id": {customerId}},
     "orderDate": "{invoiceDate}",
     "deliveryDate": "{dueDate}",
     "orderLines": [
       {
         "description": "{description}",
         "unitPriceExcludingVatCurrency": {amount},
         "count": 1,
         "product": {"id": {productId}}
       }
     ]
   }
   ```

4. POST /invoice with:
   ```json
   {
     "order": {"id": {orderId}},
     "invoiceDate": "{invoiceDate}",
     "sendToCustomer": false
   }
   ```

5. If bank account not available (405 error on invoice), fall back to voucher:
   POST /ledger/voucher with postings:
   - Debit 1500 (Accounts Receivable): amount
   - Credit 3000 (Sales Revenue): amount

## Notes
- Always create an Order first, then convert to Invoice
- amount in orderLines is excl. VAT; Tripletex adds VAT automatically
- sendToCustomer: false (competition doesn't send emails)
- On 405/404 for invoice endpoint, use ledger voucher fallback
