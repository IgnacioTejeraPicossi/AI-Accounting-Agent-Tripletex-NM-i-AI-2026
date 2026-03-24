# ledger_analysis_projects
**Description:** Analyze ledger entries across projects and generate a summary (Tier 3)

## Fields to extract
- projects[]: Project names or IDs to analyze
- dateFrom / dateTo: Analysis period (YYYY-MM-DD)
- accounts[]: Account numbers to include (optional)

## Steps

1. GET /project?fields=id,name,number&count=100
   — Get all projects (or filter by name if specified).

2. For each project of interest:
   GET /ledger/posting?projectId={projectId}&dateFrom={dateFrom}&dateTo={dateTo}&count=200&fields=id,date,amount,account,description
   — Get postings for that project.

3. GET /ledger/account?fields=id,number,name&count=200
   — Get account names for labeling.

4. If specific accounts requested:
   GET /ledger/posting?accountId={accountId}&projectId={projectId}&dateFrom={dateFrom}&dateTo={dateTo}&count=200
   — Filter by account and project.

5. POST /ledger/voucher (correcting entry if discrepancy found):
   Only if explicitly asked to correct entries.

## Notes
- Tier 3 — up to 25 write calls (but most calls here are GET = free)
- Summarize findings in your response before stopping
- If asked to create a report, summarize per-project totals by account category
