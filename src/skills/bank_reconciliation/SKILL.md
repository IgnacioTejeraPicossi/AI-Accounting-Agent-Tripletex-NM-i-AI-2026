# bank_reconciliation
**Description:** Reconcile bank statement transactions against ledger entries (Tier 3)

## Fields to extract (from CSV/PDF)
- transactions[]: List of {date, description, amount, reference}
- bankAccount: Bank account number
- periodStart / periodEnd: Reconciliation period

## Steps

1. Parse the attached CSV/PDF for bank transactions.
   CSV columns typically: date, description, amount (positive=credit, negative=debit)

2. GET /bank/statement or GET /ledger/account?number=1920&fields=id,number
   — Find bank account in ledger.

3. GET /ledger/posting?accountId={bankAccountId}&dateFrom={periodStart}&dateTo={periodEnd}&count=200
   — Fetch existing ledger postings for the period.

4. Compare bank transactions vs ledger postings by amount and date.
   Identify unmatched transactions.

5. For each unmatched bank transaction, POST /ledger/voucher:
   ```json
   {
     "description": "{transaction.description}",
     "date": "{transaction.date}",
     "postings": [
       {
         "account": {"id": {bankAccountId}},
         "debitAmount": {positiveAmount or 0},
         "creditAmount": {negativeAmount or 0},
         "amountGross": {absAmount},
         "row": 1,
         "description": "{transaction.description}"
       },
       {
         "account": {"id": {counterAccountId}},
         "debitAmount": {negativeAmount or 0},
         "creditAmount": {positiveAmount or 0},
         "amountGross": {absAmount},
         "row": 2,
         "description": "{transaction.description}"
       }
     ]
   }
   ```

## Notes
- Tier 3 task — up to 25 write calls allowed
- Counter account depends on transaction type: 3000 for income, 6000 for expenses
- Match tolerance: ±1 NOK for rounding differences
