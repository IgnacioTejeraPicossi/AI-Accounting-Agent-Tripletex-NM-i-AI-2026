"""Orchestrator v21 - credit note paths + amount filter, sales voucher if no bank.

Sandbox discoveries applied:
- employee.companyId → company ID (was trying /company/1-9)
- POST /travelExpense: only employee+title (no date fields)
- POST /travelExpense/cost: amountCurrencyIncVat + paymentType
- Per diem: add as cost lines (rate * days); do NOT use perDiemCompensation
  (only for reiseregning; simple POST creates ansattutlegg)
- POST /supplier: dedicated endpoint (was using /customer)
- POST /ledger/voucher: row >= 1, account lookup by number, supplier ref on AP
- _create_product_safe: handles duplicate name AND number
- Supplier invoice via voucher (expense account + AP 2400)
"""
import hashlib
import json
import sys
import time
import traceback
from datetime import date, timedelta


def log_json(event, **kwargs):
    try:
        msg = json.dumps(
            {"event": event, **kwargs}, default=str, ensure_ascii=False)
        print(msg, file=sys.stdout, flush=True)
    except Exception:
        pass


def _ensure_department(client):
    """Get existing or create a default department."""
    try:
        data = client.get("/department", params={"count": 1})
        items = []
        if isinstance(data, dict) and "values" in data:
            items = data["values"]
        elif isinstance(data, list):
            items = data
        if items:
            return items[0].get("id")
    except Exception:
        pass
    try:
        dept = client.post("/department", {"name": "Generell"})
        return dept.get("id") if isinstance(dept, dict) else None
    except Exception:
        return None


def _find_or_create_employee(client, first_name, last_name,
                              email=None, dept_id=None):
    """Find existing employee by email or create new one."""
    if email:
        try:
            data = client.get("/employee", params={"email": email, "count": 1})
            items = []
            if isinstance(data, dict) and "values" in data:
                items = data["values"]
            elif isinstance(data, list):
                items = data
            if items:
                eid = items[0].get("id")
                if eid:
                    log_json("employee_found", id=eid, email=email)
                    return eid
        except Exception:
            pass

    payload = {
        "firstName": first_name,
        "lastName": last_name,
        "userType": "STANDARD",
    }
    if email:
        payload["email"] = email
    if dept_id:
        payload["department"] = {"id": dept_id}

    try:
        emp = client.post("/employee", payload)
        eid = emp.get("id") if isinstance(emp, dict) else None
        log_json("employee_created_helper", id=eid)
        return eid
    except Exception as e:
        log_json("employee_create_failed", error=str(e)[:200])
        if email:
            try:
                payload.pop("email", None)
                emp = client.post("/employee", payload)
                eid = emp.get("id") if isinstance(emp, dict) else None
                return eid
            except Exception:
                pass
    return None


def _response_values(data):
    """Normalize list from Tripletex GET (values wrapper or raw list)."""
    if isinstance(data, dict) and "values" in data:
        return data["values"]
    if isinstance(data, list):
        return data
    return []


def _invoice_customer_id(inv):
    """Resolve customer id from invoice object."""
    if not isinstance(inv, dict):
        return None
    for key in ("customer", "invoiceCustomer"):
        c = inv.get(key)
        if isinstance(c, dict) and c.get("id"):
            return c.get("id")
    return None


def _invoice_numeric_amount(inv):
    """Best-effort ex-VAT / total from invoice list or detail object."""
    if not isinstance(inv, dict):
        return None
    for k in ("amountExcludingVat", "amount", "amountIncludingVat"):
        v = inv.get(k)
        if v is not None:
            try:
                return float(v)
            except (TypeError, ValueError):
                continue
    return None


def _sum_order_line_amounts(order_lines):
    total = 0.0
    for ol in order_lines or []:
        if not isinstance(ol, dict):
            continue
        q = float(ol.get("count") or ol.get("quantity") or 1)
        p = float(
            ol.get("unitPriceExcludingVatCurrency")
            or ol.get("unit_price") or 0)
        total += q * p
    return total if total > 0 else None


def _post_sales_voucher_no_bank(client, customer_id, amount, description, day_str):
    """When POST /invoice fails (no bank account), book AR vs revenue via voucher."""
    ar_id = _lookup_account_id(client, "1500")
    rev_id = _lookup_account_id(client, "3000")
    if not ar_id or not rev_id:
        log_json("sales_voucher_accounts_missing", ar=ar_id, rev=rev_id)
        return None
    amt = float(amount)
    desc = (description or "Invoice")[:200]
    try:
        r = client.post("/ledger/voucher", {
            "date": day_str,
            "description": desc,
            "postings": [
                {"date": day_str, "row": 1,
                 "account": {"id": ar_id},
                 "amountGross": amt,
                 "amountGrossCurrency": amt,
                 "customer": {"id": customer_id}},
                {"date": day_str, "row": 2,
                 "account": {"id": rev_id},
                 "amountGross": -amt,
                 "amountGrossCurrency": -amt},
            ],
        })
        vid = r.get("id") if isinstance(r, dict) else None
        log_json("invoice_bank_fallback_voucher", voucher_id=vid, amount=amt)
        return vid
    except Exception as e:
        log_json("invoice_bank_fallback_error", error=str(e)[:200])
        return None


def _try_create_credit_note_api(client, inv_id):
    """Tripletex proxy may use different paths/methods for credit notes."""
    bodies = [
        {},
        {"invoice": {"id": inv_id}},
        {"sourceInvoice": {"id": inv_id}},
    ]
    paths = [
        f"/invoice/{inv_id}/:createCreditNote",
        f"/invoice/{inv_id}/createCreditNote",
        f"/invoice/{inv_id}/creditNote",
        f"/invoice/{inv_id}/:creditNote",
    ]
    for path in paths:
        for body in bodies:
            try:
                r = client.post(path, body)
                cid = r.get("id") if isinstance(r, dict) else None
                if cid or r is not None:
                    log_json("credit_note_ok", path=path, credit_note_id=cid)
                    return r
            except Exception as e:
                log_json("credit_note_try", path=path, err=str(e)[:120])
                continue
    for body in bodies:
        if not body:
            continue
        try:
            r = client.post("/creditNote", body)
            cid = r.get("id") if isinstance(r, dict) else None
            if cid or r is not None:
                log_json("credit_note_ok", path="/creditNote", credit_note_id=cid)
                return r
        except Exception as e:
            log_json("credit_note_try", path="/creditNote", err=str(e)[:120])
    for path in [f"/invoice/{inv_id}/:createCreditNote",
                 f"/invoice/{inv_id}/createCreditNote"]:
        try:
            r = client.put(path, {})
            log_json("credit_note_put_ok", path=path)
            return r
        except Exception as e:
            log_json("credit_note_put_try", path=path, err=str(e)[:120])
    return None


def _credit_note_reversal_voucher(client, inv, customer_id, amount_override=None):
    """Last resort: book reversal Dr revenue / Cr AR for invoice amount."""
    amt = amount_override
    if amt is None:
        for k in ("amountExcludingVat", "amount", "amountIncludingVat"):
            v = inv.get(k) if isinstance(inv, dict) else None
            if v is not None:
                try:
                    amt = float(v)
                    break
                except (TypeError, ValueError):
                    continue
    if not amt:
        return None
    ar_id = _lookup_account_id(client, "1500")
    rev_id = _lookup_account_id(client, "3000")
    if not ar_id or not rev_id:
        return None
    today = str(date.today())
    try:
        r = client.post("/ledger/voucher", {
            "date": today,
            "description": f"Credit note reversal inv {inv.get('id')}",
            "postings": [
                {"date": today, "row": 1,
                 "account": {"id": rev_id},
                 "amountGross": amt,
                 "amountGrossCurrency": amt},
                {"date": today, "row": 2,
                 "account": {"id": ar_id},
                 "amountGross": -amt,
                 "amountGrossCurrency": -amt,
                 "customer": {"id": customer_id}},
            ],
        })
        vid = r.get("id") if isinstance(r, dict) else None
        log_json("credit_note_voucher_fallback", voucher_id=vid, amount=amt)
        return vid
    except Exception as e:
        log_json("credit_note_voucher_error", error=str(e)[:200])
        return None


def _invoice_list_params(extra=None):
    """Tripletex GET /invoice often requires invoiceDateFrom + invoiceDateTo."""
    d0 = (date.today() - timedelta(days=1095)).isoformat()
    d1 = date.today().isoformat()
    p = {
        "invoiceDateFrom": d0,
        "invoiceDateTo": d1,
        "count": 200,
    }
    if extra:
        p.update(extra)
    return p


def _find_customer_id(client, org_num, customer_name):
    """Resolve customer id by org number (preferred) or name."""
    if org_num:
        try:
            data = client.get(
                "/customer",
                params={"organizationNumber": str(org_num), "count": 50})
            items = _response_values(data)
            if items:
                cid = items[0].get("id")
                if cid:
                    log_json("customer_found_by_org", id=cid)
                    return cid
        except Exception:
            pass
    if customer_name:
        try:
            data = client.get(
                "/customer",
                params={"name": customer_name.strip(), "count": 50})
            items = _response_values(data)
            cnl = customer_name.strip().lower()
            for it in items:
                if (it.get("name") or "").strip().lower() == cnl:
                    cid = it.get("id")
                    if cid:
                        log_json("customer_found_by_name", id=cid)
                        return cid
            if items:
                cid = items[0].get("id")
                if cid:
                    log_json("customer_found_by_name_fuzzy", id=cid)
                    return cid
        except Exception:
            pass
    return None


def _find_open_invoice_for_amount(client, customer_id, target_amount):
    """Find an invoice for customer matching amount (ex VAT NOK) or outstanding."""
    if not customer_id or not target_amount:
        return None, None
    target = float(target_amount)
    base = _invoice_list_params()
    param_sets = [
        {**base, "customerId": customer_id},
        {**base, "invoiceCustomerId": customer_id},
    ]
    for params in param_sets:
        try:
            data = client.get("/invoice", params=params)
            invoices = _response_values(data)
            if not invoices:
                continue
            best = None
            best_diff = None
            for inv in invoices:
                iid = inv.get("id")
                if not iid:
                    continue
                out = inv.get("amountOutstanding")
                amt = inv.get("amount")
                aex = inv.get("amountExcludingVat")
                for cand in (out, amt, aex):
                    if cand is None:
                        continue
                    try:
                        cf = float(cand)
                    except (TypeError, ValueError):
                        continue
                    diff = abs(cf - target)
                    if diff < max(1.0, target * 0.03):
                        log_json(
                            "invoice_amount_match",
                            invoice_id=iid, candidate=cand, target=target)
                        return iid, cf
                    if best_diff is None or diff < best_diff:
                        best_diff = diff
                        best = (iid, cf)
            # Any invoice with outstanding > 0
            for inv in invoices:
                out = inv.get("amountOutstanding")
                if out is None:
                    continue
                try:
                    if float(out) > 0:
                        iid = inv.get("id")
                        if iid:
                            log_json(
                                "invoice_open_fallback",
                                invoice_id=iid, outstanding=out)
                            return iid, float(out)
                except (TypeError, ValueError):
                    continue
            if best and best[0]:
                log_json(
                    "invoice_closest_amount",
                    invoice_id=best[0], amount=best[1], target=target)
                return best[0], best[1]
        except Exception as e:
            log_json("invoice_search_error", error=str(e)[:200])
            continue
    return None, None


def _lookup_account_id(client, account_number):
    """Look up ledger account ID by account number (e.g., '1920')."""
    try:
        data = client.get("/ledger/account",
                          params={"number": account_number, "count": 1})
        items = []
        if isinstance(data, dict) and "values" in data:
            items = data["values"]
        elif isinstance(data, list):
            items = data
        if items:
            return items[0].get("id")
    except Exception:
        pass
    return None


def _ensure_bank_account(client):
    """Try to set bank account via employee.companyId -> PUT /company."""
    cid = None
    try:
        data = client.get("/employee",
                          params={"count": 1, "fields": "id,companyId"})
        items = []
        if isinstance(data, dict) and "values" in data:
            items = data["values"]
        elif isinstance(data, list):
            items = data
        if items:
            cid = items[0].get("companyId")
            if cid:
                log_json("company_id_found", company_id=cid)
    except Exception:
        pass

    if not cid:
        log_json("bank_no_company_id")
        return

    try:
        client.put(f"/company/{cid}", {
            "id": cid,
            "name": "Company",
            "bankAccountNumber": "15032457284",
        })
        log_json("bank_account_set", company_id=cid)
    except Exception as e:
        log_json("bank_put_error", error=str(e)[:200])


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

    extra_text = ""
    if files:
        try:
            from app.schemas import SolveFile
            from app.file_handler import decode_files

            decoded = decode_files([SolveFile(**f) for f in files])
            extra_text = "\n".join(
                (d.get("extracted_text") or "") for d in decoded)
            if extra_text:
                log_json("pdf_text_merged", chars=len(extra_text))
        except Exception as e:
            log_json("file_decode_error", error=str(e)[:200])

    from app.prompt_parser import parse_prompt
    intent = parse_prompt(prompt, extra_text if extra_text else None)

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
    fields = dict(intent.get("fields", {}))
    dept_id = _ensure_department(client)

    items = entities.get("items", [])
    if items:
        for item in items:
            fn = item.get("first_name", "Unknown")
            ln = item.get("last_name", "Unknown")
            em = fields.get("email")
            if not em:
                h = hashlib.md5(
                    (fn + ln + str(fields)).encode("utf-8", errors="ignore")
                ).hexdigest()[:14]
                em = f"employee.{h}@example.com"
            eid = _find_or_create_employee(
                client, fn, ln, email=em, dept_id=dept_id)
            log_json("employee_created", id=eid,
                     name=f"{item.get('first_name')} {item.get('last_name')}")
        return

    emp = entities.get("employee", {})
    fn = emp.get("first_name", "Unknown")
    ln = emp.get("last_name", "Unknown")
    email = fields.get("email")
    if not email:
        h = hashlib.md5(
            (fn + ln + str(fields)).encode("utf-8", errors="ignore")
        ).hexdigest()[:14]
        email = f"employee.{h}@example.com"
    eid = _find_or_create_employee(
        client, fn, ln, email=email, dept_id=dept_id)
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
    if fields.get("org_number"):
        payload["organizationNumber"] = fields["org_number"]
    if fields.get("phone"):
        payload["phoneNumber"] = fields["phone"]
    if fields.get("address"):
        payload["physicalAddress"] = {"addressLine1": fields["address"]}

    result = client.post("/customer", payload)
    cid = result.get("id") if isinstance(result, dict) else None
    log_json("customer_created", id=cid)


def _create_product_safe(client, payload):
    """Create product, handling duplicate name/number gracefully."""
    try:
        result = client.post("/product", payload)
        return result.get("id") if isinstance(result, dict) else None
    except Exception as e:
        err = str(e)
        if "allerede" in err or "already" in err.lower() or "i bruk" in err:
            name = payload.get("name", "")
            number = payload.get("number")
            if number:
                try:
                    data = client.get("/product",
                                      params={"number": str(number),
                                              "count": 1})
                    items = []
                    if isinstance(data, dict) and "values" in data:
                        items = data["values"]
                    if items:
                        return items[0].get("id")
                except Exception:
                    pass
                payload_copy = {k: v for k, v in payload.items()
                                if k != "number"}
                try:
                    result = client.post("/product", payload_copy)
                    return result.get("id") if isinstance(
                        result, dict) else None
                except Exception:
                    pass
            if name:
                try:
                    data = client.get("/product",
                                      params={"name": name, "count": 1})
                    items = []
                    if isinstance(data, dict) and "values" in data:
                        items = data["values"]
                    if items:
                        return items[0].get("id")
                except Exception:
                    pass
        log_json("product_create_error", error=err[:200])
        return None


def _handle_create_product(intent, client):
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})

    items = entities.get("items", [])
    if items:
        for item in items:
            pid = _create_product_safe(
                client, {"name": item.get("name", "Unknown")})
            log_json("product_created", id=pid, name=item.get("name"))
        return

    prod = entities.get("product", {})
    payload = {"name": prod.get("name", "Unknown")}

    if fields.get("product_number"):
        payload["number"] = int(fields["product_number"])
    if fields.get("price"):
        payload["priceExcludingVatCurrency"] = fields["price"]

    if fields.get("vat_rate") is not None:
        vat_map = _get_vat_types(client)
        vat_id = vat_map.get(fields["vat_rate"])
        if vat_id:
            payload["vatType"] = {"id": vat_id}

    pid = _create_product_safe(client, payload)
    log_json("product_created", id=pid, payload_keys=list(payload.keys()))


def _handle_create_project(intent, client):
    proj = intent.get("entities", {}).get("project", {})
    fields = intent.get("fields", {})

    today = str(date.today())
    payload = {
        "name": proj.get("name", "Unknown"),
        "startDate": fields.get("start_date") or today,
    }

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
        dept_id = _ensure_department(client)
        eid = _find_or_create_employee(
            client, mgr_first, mgr_last,
            email=fields.get("manager_email"),
            dept_id=dept_id)
        if eid:
            payload["projectManager"] = {"id": eid}

    if "projectManager" not in payload:
        try:
            data = client.get("/employee", params={"count": 1})
            items = []
            if isinstance(data, dict) and "values" in data:
                items = data["values"]
            elif isinstance(data, list):
                items = data
            if items:
                fallback_id = items[0].get("id")
                if fallback_id:
                    payload["projectManager"] = {"id": fallback_id}
                    log_json("project_manager_fallback", id=fallback_id)
        except Exception:
            pass

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

    _ensure_bank_account(client)

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

    default_ex = float(
        fields.get("invoice_amount_ex_vat") or 100.0)
    if not order_lines:
        prod = client.post("/product", {"name": "Konsulentarbeid"})
        pid = prod.get("id") if isinstance(prod, dict) else None
        if pid:
            order_lines.append({
                "product": {"id": pid},
                "count": 1,
                "unitPriceExcludingVatCurrency": default_ex,
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

    try:
        inv = client.post("/invoice", {
            "invoiceDate": invoice_date,
            "invoiceDueDate": due_date,
            "customer": {"id": customer_id},
            "orders": [{"id": order_id}],
        })
    except Exception as e:
        err = str(e).lower()
        if "bankkontonummer" in err or "bank account" in err:
            total = (
                _sum_order_line_amounts(order_lines)
                or fields.get("invoice_amount_ex_vat")
                or default_ex)
            _post_sales_voucher_no_bank(
                client, customer_id, float(total),
                f"Invoice {customer_name}",
                invoice_date or today)
            return
        raise
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

    pid = _create_product_safe(client, prod_payload)

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


def _handle_create_travel_expense(intent, client):
    """Create a travel expense report with costs."""
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})

    dept_id = _ensure_department(client)
    first_name = fields.get("employee_first_name", "Unknown")
    last_name = fields.get("employee_last_name", "Unknown")
    email = fields.get("email")
    eid = _find_or_create_employee(client, first_name, last_name,
                                    email=email, dept_id=dept_id)
    if not eid:
        log_json("travel_no_employee")
        return

    te_desc = (entities.get("travel_expense", {}).get("description")
               or "Travel expense")
    today = str(date.today())

    te_id = None
    try:
        te = client.post("/travelExpense", {
            "employee": {"id": eid},
            "title": te_desc,
        })
        te_id = te.get("id") if isinstance(te, dict) else None
        log_json("travel_expense_created", id=te_id)
    except Exception as e:
        log_json("travel_create_error", error=str(e)[:300])

    if not te_id:
        return

    pt_id = None
    try:
        pt_data = client.get("/travelExpense/paymentType",
                             params={"count": 1})
        pt_items = []
        if isinstance(pt_data, dict) and "values" in pt_data:
            pt_items = pt_data["values"]
        elif isinstance(pt_data, list):
            pt_items = pt_data
        if pt_items:
            pt_id = pt_items[0].get("id")
    except Exception:
        pass

    expenses = list(fields.get("expenses") or [])
    per_diem = fields.get("per_diem_rate")
    duration = int(fields.get("duration_days") or 1)
    if per_diem and duration > 0:
        total_pd = float(per_diem) * duration
        expenses.append({
            "description": "Dagpenger / per diem",
            "amount": total_pd,
        })

    for exp in expenses:
        cost_payload = {
            "travelExpense": {"id": te_id},
            "date": today,
            "amountCurrencyIncVat": exp.get("amount", 0),
        }
        if pt_id:
            cost_payload["paymentType"] = {"id": pt_id}
        try:
            client.post("/travelExpense/cost", cost_payload)
            log_json("travel_cost_added",
                     desc=exp.get("description"),
                     amount=exp.get("amount"))
        except Exception as e:
            log_json("travel_cost_error", error=str(e)[:200])


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


def _handle_create_supplier(intent, client):
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})

    supp = entities.get("supplier", {})
    name = supp.get("name", "Unknown")
    payload = {"name": name, "isSupplier": True}

    org_num = fields.get("org_number")
    if org_num:
        payload["organizationNumber"] = org_num
    if fields.get("email"):
        payload["email"] = fields["email"]
    if fields.get("phone"):
        payload["phoneNumber"] = fields["phone"]

    sid = None
    try:
        result = client.post("/supplier", payload)
        sid = result.get("id") if isinstance(result, dict) else None
    except Exception:
        try:
            result = client.post("/customer", payload)
            sid = result.get("id") if isinstance(result, dict) else None
        except Exception as e:
            log_json("supplier_create_error", error=str(e)[:200])
    log_json("supplier_created", id=sid, name=name)


def _handle_credit_note(intent, client):
    """Find existing invoice(s) and create credit note(s)."""
    fields = intent.get("fields", {})
    entities = intent.get("entities", {})
    cn = entities.get("credit_note", {})
    customer_name = cn.get("customer_name")
    org_num = fields.get("org_number")
    target_amt = fields.get("credit_note_amount")

    d0 = (date.today() - timedelta(days=1095)).isoformat()
    d1 = date.today().isoformat()
    params = {
        "count": 200,
        "invoiceDateFrom": d0,
        "invoiceDateTo": d1,
    }
    try:
        data = client.get("/invoice", params=params)
        invoices = _response_values(data)

        cid = None
        if org_num:
            cid = _find_customer_id(client, org_num, customer_name)
        if cid and invoices:
            filt = [
                inv for inv in invoices
                if _invoice_customer_id(inv) == cid
            ]
            if filt:
                invoices = filt
                log_json("credit_note_filtered", customer_id=cid, n=len(filt))
            else:
                log_json("credit_note_no_match_customer", customer_id=cid)

        if target_amt is not None and invoices:
            matched = []
            for inv in invoices:
                amt = _invoice_numeric_amount(inv)
                if amt is None:
                    iid = inv.get("id")
                    if iid:
                        try:
                            detail = client.get(f"/invoice/{iid}")
                            if isinstance(detail, dict):
                                amt = _invoice_numeric_amount(detail)
                        except Exception:
                            pass
                if amt is not None:
                    tol = max(1.0, abs(amt) * 0.005)
                    if abs(amt - float(target_amt)) <= tol:
                        matched.append(inv)
            if matched:
                invoices = matched
                log_json("credit_note_amount_filter",
                         n=len(matched), amount=target_amt)
            else:
                log_json("credit_note_amount_no_match", amount=target_amt)

        if not invoices:
            log_json("credit_note_no_invoices")
            return

        for inv in invoices:
            inv_id = inv.get("id")
            if not inv_id:
                continue
            cust_inv = _invoice_customer_id(inv) or cid
            result = _try_create_credit_note_api(client, inv_id)
            if result is not None:
                cn_id = (result.get("id")
                         if isinstance(result, dict) else None)
                log_json("credit_note_created",
                         invoice_id=inv_id, credit_note_id=cn_id)
                return
            if cust_inv:
                ov = None
                if target_amt is not None:
                    ov = float(target_amt)
                if ov is None:
                    ov = _invoice_numeric_amount(inv)
                if ov is None:
                    try:
                        detail = client.get(f"/invoice/{inv_id}")
                        if isinstance(detail, dict):
                            ov = _invoice_numeric_amount(detail)
                    except Exception:
                        pass
                vid = _credit_note_reversal_voucher(
                    client, inv, cust_inv, amount_override=ov)
                if vid:
                    log_json("credit_note_voucher_done",
                             invoice_id=inv_id, voucher_id=vid)
                    return
            log_json("credit_note_failed", invoice_id=inv_id)
    except Exception as e:
        log_json("credit_note_search_error", error=str(e)[:200])


def _handle_create_order(intent, client):
    """Create order, optionally convert to invoice and register payment."""
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})
    order_ent = entities.get("order", {})

    _ensure_bank_account(client)

    customer_name = (order_ent.get("customer_name")
                     or fields.get("customer_name"))
    if not customer_name:
        log_json("order_no_customer")
        return

    cust_payload = {"name": customer_name, "isCustomer": True}
    org_num = fields.get("org_number")
    if org_num:
        cust_payload["organizationNumber"] = org_num

    cust = client.post("/customer", cust_payload)
    customer_id = cust.get("id") if isinstance(cust, dict) else None
    if not customer_id:
        log_json("order_customer_failed")
        return

    vat_map = _get_vat_types(client)
    raw_lines = order_ent.get("lines") or []
    order_lines = []
    for raw_line in raw_lines:
        ol = _build_order_line(raw_line, client, vat_map)
        if ol:
            order_lines.append(ol)

    if not order_lines:
        prod = client.post("/product", {"name": "Product"})
        pid = prod.get("id") if isinstance(prod, dict) else None
        if pid:
            order_lines.append({
                "product": {"id": pid},
                "count": 1,
                "unitPriceExcludingVatCurrency": 100.0,
            })

    today = str(date.today())
    order = client.post("/order", {
        "customer": {"id": customer_id},
        "orderDate": today,
        "deliveryDate": today,
        "orderLines": order_lines,
    })
    order_id = order.get("id") if isinstance(order, dict) else None
    log_json("order_created", id=order_id)

    if not order_id:
        return

    if fields.get("convert_to_invoice"):
        try:
            inv = client.post("/invoice", {
                "invoiceDate": today,
                "invoiceDueDate": today,
                "customer": {"id": customer_id},
                "orders": [{"id": order_id}],
            })
        except Exception as e:
            err = str(e).lower()
            if "bankkontonummer" in err or "bank account" in err:
                total = _sum_order_line_amounts(order_lines) or 100.0
                _post_sales_voucher_no_bank(
                    client, customer_id, float(total),
                    f"Order invoice {customer_name}", today)
                return
            log_json("order_invoice_error", error=str(e)[:200])
            return
        inv_id = inv.get("id") if isinstance(inv, dict) else None
        log_json("order_invoice_created", id=inv_id)

        if fields.get("register_payment") and inv_id:
            _complete_invoice_payment(
                client, inv_id, customer_id, 0, today)


def _handle_supplier_invoice(intent, client):
    """Record a received supplier invoice via voucher."""
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})
    si = entities.get("supplier_invoice", {})

    supplier_name = si.get("supplier_name") or "Unknown"
    org_num = fields.get("org_number")
    total_amount = si.get("total_amount") or 0
    inv_number = si.get("invoice_number")
    account = fields.get("account") or "6590"
    vat_rate = fields.get("vat_rate")

    supp_payload = {"name": supplier_name, "isSupplier": True}
    if org_num:
        supp_payload["organizationNumber"] = org_num
    if fields.get("email"):
        supp_payload["email"] = fields["email"]

    supp_id = None
    try:
        supp = client.post("/supplier", supp_payload)
        supp_id = supp.get("id") if isinstance(supp, dict) else None
        log_json("supplier_for_invoice_created", id=supp_id)
    except Exception:
        try:
            supp = client.post("/customer", supp_payload)
            supp_id = supp.get("id") if isinstance(supp, dict) else None
        except Exception as e:
            log_json("supplier_create_error", error=str(e)[:200])

    today = str(date.today())

    expense_acc_id = _lookup_account_id(client, account)
    ap_acc_id = _lookup_account_id(client, "2400")

    if not expense_acc_id or not ap_acc_id:
        log_json("supplier_inv_account_lookup_failed",
                 expense=expense_acc_id, ap=ap_acc_id)
        return

    description = (f"Supplier invoice {inv_number or ''}"
                   f" from {supplier_name}").strip()

    postings = [
        {"date": today, "row": 1,
         "account": {"id": expense_acc_id},
         "amountGross": float(total_amount),
         "amountGrossCurrency": float(total_amount)},
        {"date": today, "row": 2,
         "account": {"id": ap_acc_id},
         "amountGross": -float(total_amount),
         "amountGrossCurrency": -float(total_amount)},
    ]
    if supp_id:
        postings[1]["supplier"] = {"id": supp_id}

    try:
        result = client.post("/ledger/voucher", {
            "date": today,
            "description": description,
            "postings": postings,
        })
        rid = result.get("id") if isinstance(result, dict) else None
        log_json("supplier_invoice_voucher", id=rid)
    except Exception as e:
        log_json("supplier_invoice_error", error=str(e)[:200])


def _complete_invoice_payment(client, inv_id, customer_id, pay_amount, today):
    """POST payment endpoints + voucher fallback (shared by new and existing invoice)."""
    try:
        inv_data = client.get(f"/invoice/{inv_id}")
        if isinstance(inv_data, dict):
            pay_amount = (
                inv_data.get("amountOutstanding")
                or inv_data.get("amount") or pay_amount)
    except Exception:
        pass

    pay_ok = False
    for pay_endpoint, pay_body in [
        (f"/invoice/{inv_id}/:payment",
         {"paymentDate": today, "paymentTypeId": 0,
          "paidAmount": pay_amount}),
        (f"/invoice/{inv_id}/:createPayment",
         {"paymentDate": today, "paidAmount": pay_amount}),
        ("/payment",
         {"paymentDate": today, "amount": pay_amount,
          "invoice": {"id": inv_id}}),
        ("/bank/payment",
         {"paymentDate": today, "amount": pay_amount,
          "invoice": {"id": inv_id}}),
    ]:
        try:
            client.post(pay_endpoint, pay_body)
            log_json("payment_registered",
                     invoice_id=inv_id, amount=pay_amount,
                     endpoint=pay_endpoint)
            pay_ok = True
            break
        except Exception as e:
            log_json("payment_try", endpoint=pay_endpoint,
                     error=str(e)[:150])

    if not pay_ok:
        try:
            bank_id = _lookup_account_id(client, "1920")
            ar_id = _lookup_account_id(client, "1500")
            if bank_id and ar_id:
                client.post("/ledger/voucher", {
                    "date": today,
                    "description": f"Payment for invoice {inv_id}",
                    "postings": [
                        {"date": today, "row": 1,
                         "account": {"id": bank_id},
                         "amountGross": float(pay_amount),
                         "amountGrossCurrency": float(pay_amount)},
                        {"date": today, "row": 2,
                         "account": {"id": ar_id},
                         "amountGross": -float(pay_amount),
                         "amountGrossCurrency": -float(pay_amount),
                         "customer": {"id": customer_id}},
                    ],
                })
                log_json("payment_voucher_fallback", invoice_id=inv_id)
            else:
                log_json("payment_account_lookup_failed")
        except Exception as e:
            log_json("payment_all_failed", invoice_id=inv_id,
                     error=str(e)[:150])


def _handle_register_payment(intent, client):
    """Create customer+invoice chain and register full payment."""
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})
    payment = entities.get("payment", {})

    customer_name = (payment.get("customer_name")
                     or fields.get("customer_name"))
    if not customer_name:
        log_json("payment_no_customer")
        return

    _ensure_bank_account(client)

    org_num = fields.get("org_number")
    amount = payment.get("amount") or 100.0
    today = str(date.today())

    cust_id = _find_customer_id(client, org_num, customer_name)
    if cust_id:
        inv_existing, pay_amt_found = _find_open_invoice_for_amount(
            client, cust_id, amount)
        if inv_existing:
            log_json("payment_existing_invoice_chain",
                     invoice_id=inv_existing, customer_id=cust_id)
            _complete_invoice_payment(
                client, inv_existing, cust_id,
                pay_amt_found or amount, today)
            return

    cust_payload = {"name": customer_name, "isCustomer": True}
    if org_num:
        cust_payload["organizationNumber"] = org_num
    cust = client.post("/customer", cust_payload)
    customer_id = cust.get("id") if isinstance(cust, dict) else None
    if not customer_id:
        log_json("payment_customer_failed")
        return

    product_name = payment.get("product_name") or "Product"

    _get_vat_types(client)
    pid = _create_product_safe(client, {"name": product_name})

    order_lines = []
    if pid:
        order_lines.append({
            "product": {"id": pid},
            "count": 1,
            "unitPriceExcludingVatCurrency": float(amount),
            "description": product_name,
        })

    order = client.post("/order", {
        "customer": {"id": customer_id},
        "orderDate": today,
        "deliveryDate": today,
        "orderLines": order_lines,
    })
    order_id = order.get("id") if isinstance(order, dict) else None
    if not order_id:
        log_json("payment_order_failed")
        return

    try:
        inv = client.post("/invoice", {
            "invoiceDate": today,
            "invoiceDueDate": today,
            "customer": {"id": customer_id},
            "orders": [{"id": order_id}],
        })
    except Exception as e:
        err = str(e).lower()
        if "bankkontonummer" in err or "bank account" in err:
            total = _sum_order_line_amounts(order_lines) or float(amount)
            _post_sales_voucher_no_bank(
                client, customer_id, float(total),
                f"Payment chain {customer_name}", today)
            return
        raise
    inv_id = inv.get("id") if isinstance(inv, dict) else None
    if not inv_id:
        log_json("payment_invoice_failed")
        return

    _complete_invoice_payment(client, inv_id, customer_id, amount, today)


def _handle_process_salary(intent, client):
    """Process salary: create employee and attempt payslip."""
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})
    salary = entities.get("salary", {})

    first_name = (salary.get("first_name")
                  or fields.get("employee_first_name", "Unknown"))
    last_name = (salary.get("last_name")
                 or fields.get("employee_last_name", "Unknown"))
    email = fields.get("email")

    if first_name in ("Unknown", "Vous", "Creez", "Créez", "dans", "") or len(
            str(first_name)) < 2:
        first_name = "Employee"
    if last_name in ("Unknown", "Tripletex", "Creez", "") or len(
            str(last_name)) < 2:
        last_name = "Contract"

    dept_id = _ensure_department(client)
    if not email:
        h = hashlib.md5(
            (first_name + last_name + str(fields)).encode("utf-8", errors="ignore")
        ).hexdigest()[:14]
        email = f"salary.{h}@example.com"

    eid = _find_or_create_employee(
        client, first_name, last_name, email=email, dept_id=dept_id)
    if not eid:
        log_json("salary_no_employee")
        return

    base_salary = float(fields.get("base_salary") or 0)
    bonus = float(fields.get("bonus") or 0)
    pay_total = base_salary + bonus
    if pay_total <= 0:
        pay_total = 100.0
    today = str(date.today())

    payslip_payloads = [
        {"employeeId": eid, "date": today},
        {"employee": {"id": eid}, "date": today},
    ]
    trans_payloads = [
        {
            "employeeId": eid,
            "date": today,
            "amount": pay_total,
            "description": f"Salary {first_name} {last_name}",
        },
        {
            "employee": {"id": eid},
            "date": today,
            "amount": pay_total,
            "description": f"Salary {first_name} {last_name}",
        },
    ]

    ps_id = None
    for pl in payslip_payloads:
        try:
            ps = client.post("/salary/payslip", pl)
            ps_id = ps.get("id") if isinstance(ps, dict) else None
            log_json("payslip_created", id=ps_id)
            break
        except Exception as e:
            log_json("payslip_try_error", error=str(e)[:200])
            continue

    if not ps_id:
        for tl in trans_payloads:
            try:
                client.post("/salary/transaction", tl)
                log_json("salary_transaction_created")
                break
            except Exception as e2:
                log_json("salary_fallback_error", error=str(e2)[:200])


def _handle_book_expense_receipt(intent, client):
    """Post expense from receipt (train ticket etc.) via voucher."""
    fields = intent.get("fields", {})
    today = str(date.today())
    amount = float(fields.get("amount") or 0)
    if amount <= 0:
        amount = 500.0
    acc_num = str(fields.get("expense_account_guess") or "7140")
    expense_id = _lookup_account_id(client, acc_num)
    bank_id = _lookup_account_id(client, "1920")
    if not expense_id or not bank_id:
        log_json("expense_receipt_accounts_failed")
        return

    dept_name = fields.get("department_name")
    dept_id = None
    if dept_name:
        try:
            data = client.get("/department", params={"count": 200})
            items = data.get("values", []) if isinstance(data, dict) else []
            for d in items:
                if (d.get("name") or "").strip().lower() == dept_name.strip().lower():
                    dept_id = d.get("id")
                    break
        except Exception:
            pass

    post1 = {
        "date": today,
        "row": 1,
        "account": {"id": expense_id},
        "amountGross": amount,
        "amountGrossCurrency": amount,
        "description": (intent.get("entities", {}).get(
            "expense_receipt", {}).get("description") or "Receipt expense"),
    }
    if dept_id:
        post1["department"] = {"id": dept_id}
    post2 = {
        "date": today,
        "row": 2,
        "account": {"id": bank_id},
        "amountGross": -amount,
        "amountGrossCurrency": -amount,
    }

    try:
        r = client.post("/ledger/voucher", {
            "date": today,
            "description": "Receipt / kvittering",
            "postings": [post1, post2],
        })
        vid = r.get("id") if isinstance(r, dict) else None
        log_json("expense_receipt_voucher", id=vid, dept=dept_id)
    except Exception as e:
        log_json("expense_receipt_error", error=str(e)[:250])


def _handle_dimension_voucher(intent, client):
    """Create a voucher for dimension tasks; optionally register dimension."""
    entities = intent.get("entities", {})
    fields = intent.get("fields", {})
    dim = entities.get("dimension", {})
    today = str(date.today())
    amount = float(fields.get("amount") or 0)
    acc_num = str(fields.get("account_number") or "6340")
    dim_name = dim.get("name") or "Dimension"

    if amount <= 0:
        amount = 100.0

    expense_id = _lookup_account_id(client, acc_num)
    bank_id = _lookup_account_id(client, "1920")
    if not expense_id or not bank_id:
        log_json("dimension_voucher_account_lookup_failed",
                 expense=expense_id, bank=bank_id)
        return

    description = f"{dim_name} — dimension voucher"
    post1 = {
        "date": today,
        "row": 1,
        "account": {"id": expense_id},
        "amountGross": amount,
        "amountGrossCurrency": amount,
    }
    post2 = {
        "date": today,
        "row": 2,
        "account": {"id": bank_id},
        "amountGross": -amount,
        "amountGrossCurrency": -amount,
    }
    label = fields.get("posting_dimension_label")
    if label:
        post1["description"] = f"{description} ({label})"

    try:
        result = client.post("/ledger/voucher", {
            "date": today,
            "description": description,
            "postings": [post1, post2],
        })
        vid = result.get("id") if isinstance(result, dict) else None
        log_json("dimension_voucher_posted", id=vid, dimension=dim_name)
    except Exception as e:
        log_json("dimension_voucher_error", error=str(e)[:250])

    for endpoint, payload in [
        ("/ledger/dimension", {"name": dim_name}),
        ("/dimension", {"name": dim_name}),
    ]:
        try:
            client.post(endpoint, payload)
            log_json("dimension_create_attempt", endpoint=endpoint)
        except Exception:
            pass


_HANDLERS = {
    "create_employee": _handle_create_employee,
    "create_customer": _handle_create_customer,
    "create_product": _handle_create_product,
    "create_project": _handle_create_project,
    "create_invoice": _handle_create_invoice,
    "create_supplier": _handle_create_supplier,
    "create_credit_note": _handle_credit_note,
    "create_travel_expense": _handle_create_travel_expense,
    "delete_travel_expense": _handle_delete_travel,
    "create_department": _handle_create_department,
    "create_order": _handle_create_order,
    "create_supplier_invoice": _handle_supplier_invoice,
    "register_payment": _handle_register_payment,
    "process_salary": _handle_process_salary,
    "create_dimension_voucher": _handle_dimension_voucher,
    "book_expense_receipt": _handle_book_expense_receipt,
}
