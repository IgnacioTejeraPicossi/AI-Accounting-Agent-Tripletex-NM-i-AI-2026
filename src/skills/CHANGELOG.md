# Skills Changelog

## 2026-03-24 — Initial LLM-based architecture
- Migrated from regex + hardcoded handlers to Claude Opus 4.6 + skill files
- Created 17 SKILL.md files covering all competition task types
- Added progressive skill disclosure: system prompt ~800 tokens, full body on demand
- Added search-first pattern documented in each skill
- Added Tier 3 cap (25 write calls) for complex workflow skills

## Skills Tier Classification
**Tier 1 (max 12 write calls):** create_customer, create_employee, create_product,
  create_project, create_invoice, create_supplier, create_departments, reverse_payment,
  register_payment, create_credit_note

**Tier 2 (max 12 write calls):** create_employee_from_contract, pdf_supplier_invoice,
  create_multi_line_invoice, order_invoice_payment, register_supplier_invoice,
  receipt_expense, create_dimension_and_entry, register_travel_expense

**Tier 3 (max 25 write calls):** bank_reconciliation, full_project_cycle,
  ledger_analysis_projects, ledger_error_correction, month_end_closing,
  onboard_employee_offer_letter, overdue_invoice_reminder, project_billing,
  foreign_currency_payment
