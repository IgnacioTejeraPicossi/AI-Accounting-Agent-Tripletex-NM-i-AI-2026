# create_dimension_and_entry
**Description:** Create an accounting dimension and post a ledger entry with that dimension

## Fields to extract
- dimensionName: Name of the dimension/project dimension (required)
- amount: Posting amount (required)
- debitAccount: Debit account number (e.g. 6000 for expense)
- creditAccount: Credit account number (e.g. 1920 for bank)
- description: Posting description
- date: Posting date YYYY-MM-DD (default today)

## Steps

1. GET /project?name={dimensionName}&fields=id,name
   — Check if project/dimension exists (Tripletex uses projects as dimensions).

2. If not found, POST /project:
   ```json
   {
     "name": "{dimensionName}",
     "startDate": "{date}",
     "isInternal": true
   }
   ```

3. GET /ledger/account?number={debitAccount}&fields=id,number
   — Resolve debit account ID.

4. GET /ledger/account?number={creditAccount}&fields=id,number
   — Resolve credit account ID.

5. POST /ledger/voucher with dimension reference:
   ```json
   {
     "description": "{description}",
     "date": "{date}",
     "postings": [
       {
         "account": {"id": {debitAccountId}},
         "project": {"id": {projectId}},
         "debitAmount": {amount},
         "creditAmount": 0,
         "amountGross": {amount},
         "row": 1,
         "description": "{description}"
       },
       {
         "account": {"id": {creditAccountId}},
         "creditAmount": {amount},
         "debitAmount": 0,
         "amountGross": {amount},
         "row": 2,
         "description": "{description}"
       }
     ]
   }
   ```

## Notes
- Tripletex dimensions are implemented via project references in postings
- row starts at 1
- debitAccount defaults to 6000 if not specified; creditAccount to 1920
