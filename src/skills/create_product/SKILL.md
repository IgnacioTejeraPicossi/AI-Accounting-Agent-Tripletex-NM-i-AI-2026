# create_product
**Description:** Create a new product or service item in Tripletex

## Fields to extract
- name: Product name (required)
- number: Product/SKU number (optional)
- costExcludingVatCurrency: Unit price excl. VAT
- priceExcludingVatCurrency: Sales price excl. VAT
- vatType: VAT percentage (25, 15, 12, 0)

## Steps

1. GET /product?name={name}&fields=id,name,number
   — Check if product already exists by name.

2. If number provided: GET /product?number={number}&fields=id,name,number
   — Also check by product number.

3. GET /ledger/vatType?fields=id,name,percentage
   — Look up VAT type ID matching the desired percentage.
   Common: HIGH=25%, MIDDLE=15%, LOW=12%, NONE=0%

4. If not found, POST /product with:
   ```json
   {
     "name": "{name}",
     "number": "{number or omit}",
     "costExcludingVatCurrency": {cost},
     "priceExcludingVatCurrency": {price},
     "vatType": {"id": {vatTypeId}}
   }
   ```

## Notes
- vatType is an object with id, not a plain number
- If no VAT rate specified, use HIGH (25%) for most goods/services in Norway
- priceExcludingVatCurrency and costExcludingVatCurrency are both recommended
