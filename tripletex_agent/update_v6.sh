#!/usr/bin/env bash
set -euo pipefail

echo "=== v6: Employee userType fix + resilient project handler ==="

# --- Only orchestrator.py changes ---
cat > ~/tripletex_agent/app/orchestrator.py << 'PYEOF'
"""Orchestrator v6 - employee userType + resilient project handler.

Key fixes:
- All employee creation includes userType: STANDARD (fixes 422 Brukertype error)
- Project handler wraps customer/employee creation in try/except so project always gets created
"""
import json
import sys
import time
import traceback
from datetime import date


def log_json(event, **kwargs):
    try:
        msg = json.dumps(
            {"event": event, **kwargs}, default=str, ensure_ascii=False)
        print(msg, file=sys.stdout, flush=True)
    except Exception:
        pass


def solve_task(body):
    start = time.time()

    prompt = body.get("prompt", "")
    files = body.get("files") or []
    creds = body.get("tripletex_credentials") or {}
    base_url = str(creds.get("base_url", "")).strip()
    session_token = str(creds.get("session_token", "")).strip()

    log_json("solve_started",
             prompt=prompt,
             base_url=base_url,
             token_length=len(session_token),
             files_count=len(files))

    if not base_url or not session_token:
        log_json("missing_credentials")
        return

    from app.prompt_parser import parse_prompt
    intent = parse_prompt(prompt)

    safe_fields = {
        k: v for k, v in intent.get("fields", {}).items()
        if k != "raw_prompt"
    }
    log_json("intent_parsed",
             task_type=intent["task_type"],
             action=intent["action"],
             language=intent["language"],
             entities=intent.get("entities", {}),
             fields=safe_fields)

    from app.tripletex_client import TripletexClient
    client = TripletexClient(base_url, session_token)

    task_type = intent["task_type"]

    try:
        handler = _HANDLERS.get(task_type)
        if handler:
            handler(intent, client)
        else:
            log_json("unsupported_task", task_type=task_type)
    except Exception as e:
        log_json("workflow_error",
                 task_type=task_type,
                 error=str(e),
                 tb=traceback.format_exc()[-1000:])

    elapsed = int((time.time() - start) * 1000)
    log_json("solve_completed", task_type=task_type, elapsed_ms=elapsed)


# ---------------------------------------------------------------------------
# Workflow handlers
# ---------------------------------------------------------------------------

def _handle_create_employee(intent, client):
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})

    items = entities.get("items", [])
    if items:
        for item in items:
            payload = {
                "firstName": item.get("first_name", "Unknown"),
                "lastName": item.get("last_name", "Unknown"),
                "userType": "STANDARD",
            }
            result = client.post("/employee", payload)
            eid = result.get("id") if isinstance(result, dict) else None
            log_json("employee_created", id=eid,
                     name=f"{item.get('first_name')} {item.get('last_name')}")
        return

    emp = entities.get("employee", {})
    payload = {
        "firstName": emp.get("first_name", "Unknown"),
        "lastName": emp.get("last_name", "Unknown"),
        "userType": "STANDARD",
    }
    if fields.get("email"):
        payload["email"] = fields["email"]
    if fields.get("phone"):
        payload["mobileNumber"] = fields["phone"]

    result = client.post("/employee", payload)
    eid = result.get("id") if isinstance(result, dict) else None
    log_json("employee_created", id=eid)


def _handle_create_customer(intent, client):
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})

    items = entities.get("items", [])
    if items:
        for item in items:
            payload = {"name": item.get("name", "Unknown"), "isCustomer": True}
            result = client.post("/customer", payload)
            cid = result.get("id") if isinstance(result, dict) else None
            log_json("customer_created", id=cid, name=item.get("name"))
        return

    cust = entities.get("customer", {})
    payload = {"name": cust.get("name", "Unknown"), "isCustomer": True}
    if fields.get("email"):
        payload["email"] = fields["email"]

    result = client.post("/customer", payload)
    cid = result.get("id") if isinstance(result, dict) else None
    log_json("customer_created", id=cid)


def _handle_create_product(intent, client):
    entities = intent.get("entities", {})

    items = entities.get("items", [])
    if items:
        for item in items:
            payload = {"name": item.get("name", "Unknown")}
            result = client.post("/product", payload)
            pid = result.get("id") if isinstance(result, dict) else None
            log_json("product_created", id=pid, name=item.get("name"))
        return

    prod = entities.get("product", {})
    payload = {"name": prod.get("name", "Unknown")}

    result = client.post("/product", payload)
    pid = result.get("id") if isinstance(result, dict) else None
    log_json("product_created", id=pid)


def _handle_create_project(intent, client):
    proj = intent.get("entities", {}).get("project", {})
    fields = intent.get("fields", {})

    payload = {"name": proj.get("name", "Unknown")}

    customer_name = fields.get("customer_name")
    if customer_name:
        cust_payload = {"name": customer_name, "isCustomer": True}
        org_num = fields.get("org_number")
        if org_num:
            cust_payload["organizationNumber"] = org_num
        try:
            cust = client.post("/customer", cust_payload)
            cid = cust.get("id") if isinstance(cust, dict) else None
            if cid:
                payload["customer"] = {"id": cid}
        except Exception as e:
            log_json("project_customer_error", error=str(e)[:200])

    mgr_first = fields.get("manager_first_name")
    mgr_last = fields.get("manager_last_name")
    if mgr_first and mgr_last:
        emp_payload = {
            "firstName": mgr_first,
            "lastName": mgr_last,
            "userType": "STANDARD",
        }
        mgr_email = fields.get("manager_email")
        if mgr_email:
            emp_payload["email"] = mgr_email
        try:
            emp = client.post("/employee", emp_payload)
            eid = emp.get("id") if isinstance(emp, dict) else None
            if eid:
                payload["projectManager"] = {"id": eid}
        except Exception as e:
            log_json("project_manager_error", error=str(e)[:200])

    if fields.get("description"):
        payload["description"] = fields["description"]
    if fields.get("start_date"):
        payload["startDate"] = fields["start_date"]
    if fields.get("end_date"):
        payload["endDate"] = fields["end_date"]

    result = client.post("/project", payload)
    pid = result.get("id") if isinstance(result, dict) else None
    log_json("project_created", id=pid)


def _get_vat_types(client):
    """Fetch available VAT types, return dict mapping percentage -> id."""
    vat_map = {}
    try:
        data = client.get("/ledger/vatType", params={"count": 100})
        items = []
        if isinstance(data, dict) and "values" in data:
            items = data["values"]
        elif isinstance(data, list):
            items = data
        for item in items:
            pct = item.get("percentage")
            vid = item.get("id")
            if pct is not None and vid is not None:
                pct_int = int(float(pct))
                if pct_int not in vat_map:
                    vat_map[pct_int] = vid
        log_json("vat_types_loaded", count=len(vat_map),
                 rates=list(vat_map.keys()))
    except Exception as e:
        log_json("vat_lookup_skipped", error=str(e)[:200])
    return vat_map


def _handle_create_invoice(intent, client):
    invoice = intent.get("entities", {}).get("invoice", {})
    fields = intent.get("fields", {})

    customer_name = (
        invoice.get("customer_name") or fields.get("customer_name"))
    raw_lines = invoice.get("lines") or []
    invoice_date = invoice.get("invoice_date") or str(date.today())
    due_date = invoice.get("due_date") or invoice_date

    if not customer_name:
        log_json("invoice_no_customer",
                 prompt=intent.get("raw_prompt", "")[:500])
        return

    cust_payload = {"name": customer_name, "isCustomer": True}
    org_num = fields.get("org_number")
    if org_num:
        cust_payload["organizationNumber"] = org_num

    cust = client.post("/customer", cust_payload)
    customer_id = cust.get("id") if isinstance(cust, dict) else None
    if not customer_id:
        log_json("invoice_customer_failed", response=str(cust)[:300])
        return

    vat_map = _get_vat_types(client)

    order_lines = []
    for raw_line in raw_lines:
        ol = _build_order_line(raw_line, client, vat_map)
        if ol:
            order_lines.append(ol)

    if not order_lines:
        prod = client.post("/product", {"name": "Konsulentarbeid"})
        pid = prod.get("id") if isinstance(prod, dict) else None
        if pid:
            order_lines.append({
                "product": {"id": pid},
                "count": 1,
                "unitPriceExcludingVatCurrency": 100.0,
                "description": "Konsulentarbeid",
            })

    if not order_lines:
        log_json("invoice_no_lines")
        return

    today = str(date.today())
    order = client.post("/order", {
        "customer": {"id": customer_id},
        "orderDate": invoice_date or today,
        "deliveryDate": invoice_date or today,
        "orderLines": order_lines,
    })
    order_id = order.get("id") if isinstance(order, dict) else None
    if not order_id:
        log_json("invoice_order_failed", response=str(order)[:500])
        return

    inv = client.post("/invoice", {
        "invoiceDate": invoice_date,
        "invoiceDueDate": due_date,
        "customer": {"id": customer_id},
        "orders": [{"id": order_id}],
    })
    inv_id = inv.get("id") if isinstance(inv, dict) else None
    log_json("invoice_created", id=inv_id, order_id=order_id)


def _build_order_line(raw_line, client, vat_map=None):
    if not isinstance(raw_line, dict):
        return None

    quantity = raw_line.get("quantity", 1)
    unit_price = raw_line.get("unit_price", 100.0)
    product_name = raw_line.get("product_name", "Product")
    product_number = raw_line.get("product_number")
    vat_rate = raw_line.get("vat_rate")

    prod_payload = {"name": product_name}
    if product_number:
        prod_payload["number"] = int(product_number)
    if vat_rate is not None and vat_map:
        vat_id = vat_map.get(vat_rate)
        if vat_id:
            prod_payload["vatType"] = {"id": vat_id}

    prod = client.post("/product", prod_payload)
    pid = prod.get("id") if isinstance(prod, dict) else None

    line = {"count": int(quantity), "description": product_name}
    if pid:
        line["product"] = {"id": pid}
    if unit_price:
        line["unitPriceExcludingVatCurrency"] = float(unit_price)
    if vat_rate is not None and vat_map:
        vat_id = vat_map.get(vat_rate)
        if vat_id:
            line["vatType"] = {"id": vat_id}
    return line


def _handle_delete_travel(intent, client):
    data = client.get(
        "/travelExpense", params={"fields": "id", "count": 100})

    expenses = []
    if isinstance(data, dict) and "values" in data:
        expenses = data["values"]
    elif isinstance(data, list):
        expenses = data

    deleted = 0
    for exp in expenses:
        eid = exp.get("id")
        if eid:
            try:
                client.delete(f"/travelExpense/{eid}")
                deleted += 1
            except Exception as e:
                log_json("delete_travel_fail", id=eid, error=str(e))

    log_json("travel_deleted", count=deleted)


def _handle_create_department(intent, client):
    entities = intent.get("entities", {})

    items = entities.get("items", [])
    if items:
        for item in items:
            name = item.get("name", "Unknown")
            result = client.post("/department", {"name": name})
            did = result.get("id") if isinstance(result, dict) else None
            log_json("department_created", id=did, name=name)
        return

    dept = entities.get("department", {})
    name = dept.get("name", "Unknown")

    result = client.post("/department", {"name": name})
    did = result.get("id") if isinstance(result, dict) else None
    log_json("department_created", id=did)


_HANDLERS = {
    "create_employee": _handle_create_employee,
    "create_customer": _handle_create_customer,
    "create_product": _handle_create_product,
    "create_project": _handle_create_project,
    "create_invoice": _handle_create_invoice,
    "delete_travel_expense": _handle_delete_travel,
    "create_department": _handle_create_department,
}
PYEOF

echo "  [OK] orchestrator.py updated"

# --- Deploy ---
echo "=== Deploying v6 to Cloud Run ==="
cd ~/tripletex_agent
gcloud run deploy tripletex-agent \
  --source . \
  --region europe-north1 \
  --allow-unauthenticated \
  --memory 1Gi \
  --timeout 300

echo "=== Done! ==="
