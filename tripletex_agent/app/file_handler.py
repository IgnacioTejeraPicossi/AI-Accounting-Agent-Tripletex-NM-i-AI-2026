import base64
import tempfile
from pathlib import Path

from app.schemas import SolveFile


def decode_files(files: list[SolveFile]) -> list[dict]:
    if not files:
        return []

    output = []
    temp_dir = Path(tempfile.mkdtemp(prefix="tripletex_files_"))

    for f in files:
        raw = base64.b64decode(f.content_base64)
        target = temp_dir / f.filename
        target.write_bytes(raw)

        extracted_text = ""
        if f.mime_type == "application/pdf":
            extracted_text = _extract_pdf_text_safe(target)

        output.append(
            {
                "filename": f.filename,
                "mime_type": f.mime_type,
                "path": str(target),
                "size_bytes": len(raw),
                "extracted_text": extracted_text,
            }
        )

    return output


def _extract_pdf_text_safe(path: Path) -> str:
    try:
        from pypdf import PdfReader

        reader = PdfReader(str(path))
        return "\n".join(page.extract_text() or "" for page in reader.pages).strip()
    except Exception:
        return ""
