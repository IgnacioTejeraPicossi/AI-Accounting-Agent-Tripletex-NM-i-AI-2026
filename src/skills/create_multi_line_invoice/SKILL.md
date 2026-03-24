# create_multi_line_invoice
**Description:** Create an invoice with multiple line items for a customer

## Fields to extract
- customer: Customer name or org number (required)
- lines[]: Array of {description, amount, quantity, product} (required)
- invoiceDate: YYYY-MM-DD (default today)
- dueDate: YYYY-MM-DD (default +14 days)

## Steps

1. GET /customer?name={customerName}&fields=id,name
   — Resolve customer ID.

2. For each line that references a product:
   GET /product?name={productName}&fields=id,name,priceExcludingVatCurrency
   — Resolve product ID per line.

3. POST /order with multiple orderLines:
   ```json
   {
     "customer": {"id": {customerId}},
     "orderDate": "{invoiceDate}",
     "deliveryDate": "{dueDate}",
     "orderLines": [
       {
         "description": "{line1.description}",
         "unitPriceExcludingVatCurrency": {line1.amount},
         "count": {line1.quantity or 1},
         "product": {"id": {line1.productId or omit}}
       },
       {
         "description": "{line2.description}",
         "unitPriceExcludingVatCurrency": {line2.amount},
         "count": {line2.quantity or 1}
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

## Notes
- Build all order lines in a single POST /order — do not create multiple orders
- Each line can optionally reference a product; description is always required
- count defaults to 1 if not specified
