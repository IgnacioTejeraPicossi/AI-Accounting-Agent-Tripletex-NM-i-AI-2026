"""Agent loop — LLM interaction and tool execution."""
import base64
import json
import logging
import os
from pathlib import Path
from typing import Any

import anthropic
import httpx

from skills.registry import SkillRegistry

log = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format="%(message)s")

MODEL = "claude-opus-4-6"
MAX_TOKENS = 4096
MAX_ITERATIONS = 60

# Write calls (POST/PUT/DELETE) count against quota; GETs are free
TIER3_SKILLS = {
    "bank_reconciliation", "full_project_cycle", "ledger_analysis_projects",
    "ledger_error_correction", "month_end_closing", "onboard_employee_offer_letter",
    "overdue_invoice_reminder", "project_billing", "foreign_currency_payment",
}
TIER2_SKILLS = {
    "create_employee_from_contract", "pdf_supplier_invoice", "create_multi_line_invoice",
    "order_invoice_payment", "register_supplier_invoice", "receipt_expense",
    "create_dimension_and_entry",
}
MAX_CALLS = {1: 12, 2: 12, 3: 25}

_registry = SkillRegistry(Path(__file__).parent / "skills")

# ── Tool schemas ─────────────────────────────────────────────────────────────

USE_SKILL_TOOL = {
    "name": "use_skill",
    "description": (
        "Load the full step-by-step instructions for a skill. "
        "Call this FIRST after reading the task prompt, with the skill name that best matches."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "skill_name": {
                "type": "string",
                "description": "Exact skill name, e.g. 'create_customer' or 'register_payment'.",
            }
        },
        "required": ["skill_name"],
    },
}

TRIPLETEX_API_TOOL = {
    "name": "tripletex_api",
    "description": (
        "Make an authenticated REST call to the Tripletex API. "
        "GET calls are FREE (do not count against quota). "
        "POST / PUT / DELETE each count as 1 write call. "
        "Always search (GET) before creating (POST) to avoid duplicates."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "method": {"type": "string", "enum": ["GET", "POST", "PUT", "DELETE"]},
            "path": {
                "type": "string",
                "description": "API path starting with /, e.g. '/customer' or '/employee/1234'.",
            },
            "params": {
                "type": "object",
                "description": "Query-string parameters for GET requests.",
            },
            "body": {
                "type": "object",
                "description": "JSON request body for POST/PUT requests.",
            },
        },
        "required": ["method", "path"],
    },
}

# ── System prompt ─────────────────────────────────────────────────────────────

def _build_system_prompt() -> str:
    skill_lines = "\n".join(
        f"- {name}: {meta['description']}" for name, meta in _registry.list_skills()
    )
    return f"""You are a Tripletex accounting agent competing in NM i AI 2026.
Your job: read the user's task, call use_skill to load instructions, then execute via tripletex_api.

## Rules
1. Call use_skill FIRST with the best matching skill name.
2. Follow the skill's numbered steps exactly.
3. ALWAYS GET before POST — search for existing entities to avoid duplicates.
4. Only POST/PUT/DELETE count against your write-call quota; GETs are free.
5. When done, stop calling tools. The system returns {{"status": "completed"}} automatically.

## Available skills
{skill_lines}
"""


# ── Tripletex HTTP client ─────────────────────────────────────────────────────

def _tripletex_call(credentials: dict, method: str, path: str,
                    params: dict | None = None, body: dict | None = None) -> Any:
    base_url = credentials.get("base_url", "").rstrip("/")
    token = credentials.get("session_token", "")
    url = f"{base_url}/v2{path}"
    auth = ("0", token)

    log.info(json.dumps({"event": "api", "method": method, "path": path}))

    with httpx.Client(timeout=30) as client:
        if method == "GET":
            r = client.get(url, params=params or {}, auth=auth)
        elif method == "POST":
            r = client.post(url, json=body or {}, auth=auth)
        elif method == "PUT":
            r = client.put(url, json=body or {}, auth=auth)
        elif method == "DELETE":
            r = client.delete(url, auth=auth)
        else:
            return {"error": f"Unknown method: {method}"}

    log.info(json.dumps({"event": "api_response", "method": method, "path": path, "status": r.status_code}))

    if r.status_code >= 400:
        return {"error": r.status_code, "body": r.text[:500]}

    if not r.content:
        return {"status": "ok"}

    try:
        data = r.json()
        # Unwrap Tripletex's {"value": ...} envelope
        if isinstance(data, dict) and "value" in data:
            return data["value"]
        return data
    except Exception:
        return {"raw": r.text[:500]}


# ── File extraction ───────────────────────────────────────────────────────────

def _extract_files(files: list[dict]) -> str:
    texts = []
    for f in files:
        name = f.get("filename", "file")
        mime = f.get("mime_type", "")
        b64 = f.get("content_base64", "")
        if not b64:
            continue
        raw = base64.b64decode(b64)
        if "pdf" in mime.lower() or name.lower().endswith(".pdf"):
            try:
                import pypdf, io
                reader = pypdf.PdfReader(io.BytesIO(raw))
                text = "\n".join(p.extract_text() or "" for p in reader.pages)
                texts.append(f"[{name}]\n{text}")
            except Exception as e:
                texts.append(f"[{name}] (PDF parse error: {e})")
        else:
            try:
                texts.append(f"[{name}]\n{raw.decode('utf-8', errors='replace')}")
            except Exception:
                texts.append(f"[{name}] (binary, cannot decode)")
    return "\n\n".join(texts)


# ── Agent loop ────────────────────────────────────────────────────────────────

async def run_agent(
    prompt: str,
    files: list[dict],
    credentials: dict,
    run_dir: Path,
) -> dict:
    client = anthropic.Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY"))

    # Build user message
    file_text = _extract_files(files)
    user_content = prompt
    if file_text:
        user_content += f"\n\n--- Attached files ---\n{file_text}"

    messages: list[dict] = [{"role": "user", "content": user_content}]
    system_prompt = _build_system_prompt()

    write_calls = 0
    selected_skill: str | None = None
    api_calls_log: list[dict] = []
    iterations = 0

    log.info(json.dumps({"event": "agent_start", "prompt_len": len(prompt)}))

    while iterations < MAX_ITERATIONS:
        iterations += 1

        response = client.messages.create(
            model=MODEL,
            system=system_prompt,
            messages=messages,
            tools=[USE_SKILL_TOOL, TRIPLETEX_API_TOOL],
            max_tokens=MAX_TOKENS,
        )

        # Append assistant turn
        messages.append({"role": "assistant", "content": response.content})

        if response.stop_reason == "end_turn":
            log.info(json.dumps({"event": "agent_done", "write_calls": write_calls, "iterations": iterations}))
            break

        # Determine tier & max calls (once skill is selected)
        if selected_skill:
            if selected_skill in TIER3_SKILLS:
                tier = 3
            elif selected_skill in TIER2_SKILLS:
                tier = 2
            else:
                tier = 1
            call_limit = MAX_CALLS[tier]
        else:
            call_limit = MAX_CALLS[1]

        # Process tool calls
        tool_results = []
        for block in response.content:
            if block.type != "tool_use":
                continue

            tool_name = block.name
            tool_input = block.input

            # ── use_skill ──────────────────────────────────────────────────
            if tool_name == "use_skill":
                skill_name = tool_input.get("skill_name", "")
                selected_skill = skill_name
                body = _registry.get_skill_body(skill_name)
                if body:
                    result = body
                    log.info(json.dumps({"event": "skill_loaded", "skill": skill_name}))
                else:
                    result = f"Skill '{skill_name}' not found. Available: {', '.join(n for n, _ in _registry.list_skills())}"

            # ── tripletex_api ──────────────────────────────────────────────
            elif tool_name == "tripletex_api":
                method = tool_input.get("method", "GET").upper()
                path = tool_input.get("path", "/")
                params = tool_input.get("params")
                body_payload = tool_input.get("body")

                is_write = method in ("POST", "PUT", "DELETE")

                # Skip logic: if quota exhausted, return informative error
                if is_write and write_calls >= call_limit:
                    result = {"error": f"Write call limit reached ({call_limit}). Task may be maxed out."}
                    log.info(json.dumps({"event": "quota_exceeded", "limit": call_limit}))
                else:
                    result = _tripletex_call(credentials, method, path, params, body_payload)
                    if is_write:
                        write_calls += 1

                api_calls_log.append({
                    "method": method,
                    "path": path,
                    "write": is_write,
                    "write_count": write_calls,
                })

            else:
                result = {"error": f"Unknown tool: {tool_name}"}

            tool_results.append({
                "type": "tool_result",
                "tool_use_id": block.id,
                "content": json.dumps(result, ensure_ascii=False)
                if isinstance(result, (dict, list))
                else str(result),
            })

        messages.append({"role": "user", "content": tool_results})

    # Save api calls log
    if run_dir:
        import asyncio
        (run_dir / "api_calls.json").write_text(
            json.dumps(api_calls_log, indent=2), encoding="utf-8"
        ) if run_dir.exists() else None

    return {"status": "completed", "write_calls": write_calls, "skill": selected_skill}
