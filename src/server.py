"""FastAPI server — /solve endpoint receives task prompts + files."""
import json
import os
import time
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from agent import run_agent

app = FastAPI(title="Tripletex AI Agent")
RUNS_DIR = Path(__file__).parent.parent / "runs"


def _save_run(run_dir: Path, data: dict) -> None:
    run_dir.mkdir(parents=True, exist_ok=True)
    for name, content in data.items():
        path = run_dir / name
        if isinstance(content, (dict, list)):
            path.write_text(json.dumps(content, indent=2, ensure_ascii=False), encoding="utf-8")
        else:
            path.write_text(str(content), encoding="utf-8")


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/solve")
@app.post("/")
async def solve(request: Request):
    body = await request.json()
    ts = datetime.utcnow().strftime("%Y-%m-%d/%H-%M-%S")
    run_dir = RUNS_DIR / ts

    prompt = body.get("prompt", "")
    files = body.get("files", [])
    credentials = body.get("tripletex_credentials", {})

    t0 = time.time()
    result = await run_agent(prompt, files, credentials, run_dir)
    elapsed = round(time.time() - t0, 2)

    _save_run(run_dir, {
        "prompt.txt": prompt,
        "meta.json": {"elapsed_s": elapsed, "ts": ts},
        "result.json": result,
    })

    return JSONResponse({"status": "completed"})
