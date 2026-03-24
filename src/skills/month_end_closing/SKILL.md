# month_end_closing
**Description:** Perform month-end closing: depreciation, accruals, period lock (Tier 3)

## Fields to extract
- period: Month/year to close (YYYY-MM)
- depreciationAmount: Fixed asset depreciation amount (optional)
- accruals[]: List of {account, amount, description} (optional)

## Steps

1. GET /ledger/account?fields=id,number,name&count=200
   — Get chart of accounts to identify relevant accounts.

2. If depreciation:
   GET /ledger/account?number=6010&fields=id,number  ← depreciation expense
   GET /ledger/account?number=1200&fields=id,number  ← accumulated depreciation
   POST /ledger/voucher (depreciation entry):
   - Debit 6010 (Depreciation expense): amount
   - Credit 1200 (Accumulated depreciation): amount

3. For each accrual:
   GET /ledger/account?number={account}&fields=id,number
   POST /ledger/voucher (accrual entry):
   - Debit expense account: amount
   - Credit accrued liabilities (2900): amount

4. POST /ledger/close or PUT /ledger/period with:
   ```json
   {"year": {year}, "month": {month}, "isClosed": true}
   ```
   — Lock the period. Attempt but do not fail if endpoint returns 405.

## Notes
- Tier 3 — up to 25 write calls
- Period lock may not be available in all sandbox setups; continue if 405
- row starts at 1 in all voucher postings
