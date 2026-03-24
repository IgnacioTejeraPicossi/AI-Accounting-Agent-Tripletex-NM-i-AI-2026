# AI Accounting Agent — NM i AI 2026

Tripletex AI Accounting Agent for the Norwegian AI Championship 2026.
---
## Architecture

Two implementations exist in this repo (testing):

| | `src/` (new) | `tripletex_agent/` (original) |
|---|---|---|
| **Approach** | Claude Opus 4.6 LLM agent | Regex parser + hardcoded handlers |
| **Task routing** | LLM selects skill from 27 SKILL.md files | 16 `_HANDLERS` in `orchestrator.py` |
| **Context size** | ~800 tokens (skill names only) | Full parser + handlers always loaded |
| **Languages** | Native (LLM understands all) | Keyword heuristics for nb/nn/en/es/pt/de/fr |
| **Status** | Current recommended approach | Competition reference (v21) |

---

## New architecture (`src/`)

### How it works

1. Platform POSTs a prompt (+ optional PDF/CSV files) to `/solve`
2. LLM reads prompt, selects matching skill via `use_skill` tool
3. Skill instructions guide exact API calls to Tripletex
4. Agent executes calls via `tripletex_api` tool, returns `{"status": "completed"}`

### Key design decisions

- **Progressive skill disclosure:** System prompt contains only skill names + descriptions (~800 tokens). Full skill body loaded on demand via `use_skill`, keeping context small.
- **Search-first pattern:** Always GET before POST to avoid duplicates.
- **Write-call quota:** Only POST/PUT/DELETE count against the limit. GETs are free.
- **Tier cap:** T1/T2 tasks: max 12 write calls. T3 (complex) tasks: max 25 write calls.
- **Skip logic:** If quota is reached, agent receives an informative error and stops gracefully.

### Tools

| Tool | Description |
|------|-------------|
| `use_skill(skill_name)` | Loads the full SKILL.md instructions for a task type |
| `tripletex_api(method, path, params, body)` | Makes authenticated REST calls to Tripletex |

### Running

```bash
cd src
pip install -r requirements.txt
export ANTHROPIC_API_KEY=sk-ant-...
python -m uvicorn server:app --host 0.0.0.0 --port 8000
```

Tunnel:

```bash
ngrok http 8000
```

### Structure

```
src/
  agent.py           — Agent loop, LLM interaction, tool execution
  server.py          — FastAPI /solve endpoint, run data saving
  requirements.txt   — fastapi, anthropic, httpx, pypdf
  Dockerfile
  skills/
    registry.py      — Discovers SKILL.md files from subdirectories
    CHANGELOG.md     — Chronological skill changes
    */SKILL.md       — 27 skill files (one per task type)
runs/
  YYYY-MM-DD/HH-MM-SS/  — Per-submission data (prompt, api_calls, meta, result)
```

### Skills

| Tier | Skills (max write calls) |
|------|--------------------------|
| **T1** (12) | `create_customer`, `create_employee`, `create_product`, `create_project`, `create_invoice`, `create_supplier`, `create_departments`, `create_credit_note`, `register_payment`, `reverse_payment` |
| **T2** (12) | `create_employee_from_contract`, `pdf_supplier_invoice`, `create_multi_line_invoice`, `order_invoice_payment`, `register_supplier_invoice`, `receipt_expense`, `create_dimension_and_entry`, `register_travel_expense` |
| **T3** (25) | `bank_reconciliation`, `full_project_cycle`, `ledger_analysis_projects`, `ledger_error_correction`, `month_end_closing`, `onboard_employee_offer_letter`, `overdue_invoice_reminder`, `project_billing`, `foreign_currency_payment` |

---

## Original architecture (`tripletex_agent/`)

The v21 competition submission. Kept as reference.

### Technical stack

| Component | Role |
|-----------|------|
| **Python 3.11** | Runtime (`python:3.11-slim`) |
| **FastAPI** + **Uvicorn** | HTTP server, port `8080` |
| **requests** | HTTP client to Tripletex proxy |
| **pypdf** | PDF text extraction |
| **Pydantic** | Request/response validation |
| **pytest** | Tests under `tripletex_agent/tests/` |

### Request flow

```
POST /solve (or POST /)
  → main.py
  → orchestrator.solve_task(body)
      → PDF text extraction (base64 → pypdf)
      → parse_prompt()          # regex-based, prompt_parser.py
      → TripletexClient(base_url, session_token)
      → _HANDLERS[task_type]    # 16 hardcoded handlers
  → {"status": "completed"}
```

### Implemented handlers

| `task_type` | Description |
|-------------|-------------|
| `create_employee` | Employee (`userType: STANDARD`) |
| `create_customer` | Customer record |
| `create_supplier` | Supplier (`POST /supplier`) |
| `create_product` | Product with VAT type lookup |
| `create_project` | Project with dates and linked customer |
| `create_invoice` | Order → Invoice; voucher 1500/3000 fallback if no bank |
| `create_order` | Order with optional invoice + payment |
| `create_credit_note` | Multiple API paths; reversal voucher 3000/1500 |
| `create_travel_expense` | Travel expense with cost lines |
| `delete_travel_expense` | Delete by listing |
| `create_department` | Department |
| `create_supplier_invoice` | Voucher 6590/2400 |
| `register_payment` | Invoice payment; voucher 1920/1500 fallback |
| `process_salary` | Payroll attempt |
| `create_dimension_voucher` | Ledger posting with dimension |
| `book_expense_receipt` | Expense with receipt and department |

### Local development

```bash
cd tripletex_agent
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
```

### Tests

```bash
cd tripletex_agent
python -m pytest tests/ -v
```

### Deployment (Google Cloud Run)

```bash
cd tripletex_agent
gcloud run deploy tripletex-agent --source . --region europe-north1 \
  --allow-unauthenticated --memory 1Gi --timeout 300 --project <PROJECT_ID>
```

### Tripletex API patterns

- **Company ID:** `GET /employee?fields=id,companyId` → `employee[0].companyId`
- **Invoice listings:** always include `invoiceDateFrom` + `invoiceDateTo` + `count`
- **Vouchers:** `row ≥ 1`, accounts resolved via `GET /ledger/account?number=...`
- **Payment paths tried:** `:payment` → `:createPayment` → `/payment` → voucher fallback
- **No IBAN:** voucher 1500 (AR) / 3000 (revenue)

---

## Implementation history

| Date | Version | Changes |
|------|---------|---------|
| 2026-03-20 | v1–v13 | Initial FastAPI service, Tripletex client, multilingual parser, iterations from scores |
| 2026-03-20 | **v14** | `POST /supplier`, vouchers with `row`, `_create_product_safe`, travel expense fix |
| 2026-03-20–21 | **v15–v21** | Dimensions, receipts, merged PDF, open-invoice lookup, salary, credit note multi-path, invoice without bank fallback |
| 2026-03 | **LLM migration** | New `src/` with Claude Opus 4.6 agent, 27 SKILL.md files, progressive skill disclosure |

---
*Documentation updated March 2026.*
