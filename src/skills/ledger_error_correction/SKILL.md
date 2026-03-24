# ledger_error_correction
**Description:** Find and correct a ledger posting error with a correcting entry (Tier 3)

## Fields to extract
- description: Description of the error or the wrong posting
- wrongAccount: Account number that was used incorrectly
- correctAccount: Account number that should have been used
- amount: Amount of the incorrect posting
- date: Date of the original posting

## Steps

1. GET /ledger/account?number={wrongAccount}&fields=id,number,name
   — Resolve wrong account ID.

2. GET /ledger/account?number={correctAccount}&fields=id,number,name
   — Resolve correct account ID.

3. GET /ledger/posting?accountId={wrongAccountId}&dateFrom={dateFrom}&dateTo={dateTo}&count=50&fields=id,date,amount,description
   — Find the original incorrect posting.

4. Post a reversing entry (undo the wrong posting):
   POST /ledger/voucher:
   - Debit {wrongAccount}: amount   ← if original was a credit
   - Credit {wrongAccount}: amount  ← if original was a debit
   (reverse the original)

5. Post the correct entry:
   POST /ledger/voucher:
   - Debit/Credit {correctAccount}: amount
   (mirror of what should have been posted originally)

## Notes
- Tier 3 — up to 25 write calls
- Two vouchers needed: one to reverse wrong posting, one to make correct posting
- If only correcting account allocation, can combine in one voucher with 3 lines
