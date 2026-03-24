# Exercise 2 (Tripletex) — Handoff for next session

Last updated: **2026-03-21**. Code status: **v21** (upload `orchestrator.py` + `prompt_parser.py`). Script: **`tripletex_agent/update_v21.sh`** (`python _gen_update_bundle.py 21`).

**Full technical documentation (architecture, API, handlers, deployment):** **`README.md`** at the workspace root.

## Where everything lives

| What | Path |
|------|------|
| FastAPI agent | `tripletex_agent/app/` |
| Main logic | `orchestrator.py`, `prompt_parser.py` |
| API client | `tripletex_client.py` |
| Plan docs | `docs/` |
| README & history | `README.md` |

## Google Cloud (as used in the competition)

- **GCP project:** `ai-nm26osl-1825`
- **Cloud Run service:** `tripletex-agent`
- **Region:** `europe-north1`
- **Tripletex proxy (competition):** URL in logs like `https://tx-proxy-....a.run.app/v2` (set by the platform)

## When you return: deploy from Cloud Shell

1. Upload **only** the files you changed locally to **`~/tripletex_agent/app/`** (not to home `~/`):
   - `orchestrator.py`
   - `prompt_parser.py`
2. If you uploaded them to home by mistake:
   ```bash
   mv ~/orchestrator.py ~/prompt_parser.py ~/tripletex_agent/app/
   ```
3. **Single command** (do not paste the service name when the prompt asks for only that):
   ```bash
   cd ~/tripletex_agent && gcloud run deploy tripletex-agent --source . --region europe-north1 --allow-unauthenticated --memory 1Gi --timeout 300 --project ai-nm26osl-1825 --quiet
   ```

## Logs (after submissions)

```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=tripletex-agent" --limit 100 --format="value(textPayload,jsonPayload)" --freshness=30m --project ai-nm26osl-1825
```

## What worked / what was still open (last session)

- **Good:** `companyId` via `GET /employee?fields=id,companyId`; payment with **voucher fallback** (`POST /ledger/voucher` 201); suppliers with `POST /supplier`; vouchers with `row >= 1` and accounts by number.
- **v21:** if `POST /invoice` fails due to **missing bank account**, try **voucher 1500/3000**; **credit notes** try several paths then **accounting reversal**; filter by amount from the prompt (`credit_note_amount`).
- **PUT /company:** still returns **405** (bank account often cannot be set via API in many environments).
- **v14.1 travel:** per diem as **cost lines** (not `perDiemCompensation`); German parser with **Auslagen** for expenses.

## Tripletex sandbox (optional)

- Use it to try real endpoints outside the proxy.
- **Do not commit tokens to Git.** Session token comes from the sandbox UI; it expires.
- Useful findings already in code: `employee.companyId`, `travelExpense/cost` shape, `POST /supplier`, `POST /ledger/voucher` with `row` and references.

## Suggested next steps when resuming

1. Deploy latest local version (at least 2 `.py` files).
2. Platform submissions and **logs**.
3. Review remaining failures (accounting dimensions, complex orders, etc.) from logs.

## Large deploy script

If you use `update_v14.sh`: upload it to Shell and run it from `~`; the file must exist where you run `bash`. Simpler alternative: **only upload the `.py` files to `tripletex_agent/app/`** + the `gcloud` command above.

---
*When reopening Cursor in this folder, read this file and `README.md` (Exercise 2 section + implementation summary).*
