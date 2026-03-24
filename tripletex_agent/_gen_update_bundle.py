"""Regenerate update_vNN.sh from app/prompt_parser.py + app/orchestrator.py."""
import argparse
from pathlib import Path


def main():
    p = argparse.ArgumentParser()
    p.add_argument("version", help="e.g. 17")
    args = p.parse_args()
    ver = args.version.strip()
    root = Path(__file__).resolve().parent

    def load(name: str) -> str:
        body = (root / "app" / name).read_text(encoding="utf-8")
        for line in body.splitlines():
            if line.strip() == "PYEOF":
                raise SystemExit(f"{name} contains forbidden line PYEOF")
        return body

    pp = load("prompt_parser.py")
    orc = load("orchestrator.py")

    lines = [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        "",
        f'echo "=== v{ver}: deploy bundle (prompt_parser + orchestrator) ==="',
        "",
    ]
    lines.append("cat > ~/tripletex_agent/app/prompt_parser.py << 'PYEOF'")
    lines.extend(pp.splitlines())
    lines.append("PYEOF")
    lines.append("")
    lines.append("cat > ~/tripletex_agent/app/orchestrator.py << 'PYEOF'")
    lines.extend(orc.splitlines())
    lines.append("PYEOF")
    lines.append("")

    out = root / f"update_v{ver}.sh"
    out.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print("Wrote", out, "bytes", out.stat().st_size)


if __name__ == "__main__":
    main()
