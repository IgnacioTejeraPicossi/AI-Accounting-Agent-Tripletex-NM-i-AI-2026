# foreign_currency_payment
**Description:** Register a payment in foreign currency (EUR, USD, GBP, etc.) with FX difference (Tier 3)

## Fields to extract
- supplier / customer: Party name
- amount: Amount in foreign currency
- currency: Currency code (EUR, USD, GBP, etc.)
- exchangeRate: Exchange rate to NOK (optional, use current if omitted)
- paymentDate: YYYY-MM-DD
- invoiceAmount: Original invoice amount (to calculate FX difference)

## Steps

1. GET /currency?code={currencyCode}&fields=id,code,factor
   — Resolve currency ID and current rate.

2. If supplier payment:
   GET /supplier?name={supplierName}&fields=id,name
   — Resolve supplier.
   GET /ledger/account?number=2400&fields=id,number  ← AP
   GET /ledger/account?number=1920&fields=id,number  ← Bank

3. Calculate NOK amount: foreignAmount × exchangeRate
   Calculate FX difference: invoiceNOK - paymentNOK

4. POST /ledger/voucher (payment with FX):
   ```json
   {
     "description": "FX payment {currency} to {supplier}",
     "date": "{paymentDate}",
     "currency": {"id": {currencyId}},
     "postings": [
       {"account": {"id": {apAccountId}}, "debitAmount": {invoiceNOK}, "creditAmount": 0, "amountGross": {invoiceNOK}, "row": 1},
       {"account": {"id": {bankAccountId}}, "debitAmount": 0, "creditAmount": {paymentNOK}, "amountGross": {paymentNOK}, "row": 2},
       {"account": {"id": {fxAccountId}}, "debitAmount": {fxGain or 0}, "creditAmount": {fxLoss or 0}, "amountGross": {absFxDiff}, "row": 3}
     ]
   }
   ```

5. FX gain/loss account: 8060 (financial income/expense).

## Notes
- Tier 3 — up to 25 write calls
- Account 8060 for FX differences
- row starts at 1
