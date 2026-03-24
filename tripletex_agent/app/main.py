import json
import sys
import traceback

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse


def log_json(event, **kwargs):
    try:
        msg = json.dumps({"event": event, **kwargs}, default=str, ensure_ascii=False)
        print(msg, file=sys.stdout, flush=True)
    except Exception:
        pass


app = FastAPI(title="Tripletex Agent", version="0.2.0")


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/solve")
@app.post("/")
async def solve(request: Request):
    try:
        body = await request.json()
    except Exception as e:
        log_json("json_parse_error", error=str(e))
        return JSONResponse({"status": "completed"})

    try:
        from app.orchestrator import solve_task
        solve_task(body)
    except Exception as e:
        log_json("solve_error", error=str(e), tb=traceback.format_exc()[-1500:])

    return JSONResponse({"status": "completed"})
