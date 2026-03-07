"""Lightweight document text extraction for email attachments."""
from __future__ import annotations

import io
import structlog

log = structlog.get_logger()

MAX_EXTRACTED_CHARS = 24_000  # ~6K tokens — enough for LLM context


def extract_text(raw_bytes: bytes, mime_type: str, filename: str = "") -> str:
    """Extract text content from a document.

    Supports: PDF, DOCX, plain text, CSV, HTML.
    Returns empty string for unsupported types.
    """
    mime = mime_type.lower()
    fname = filename.lower()

    try:
        if mime == "application/pdf" or fname.endswith(".pdf"):
            return _extract_pdf(raw_bytes)
        elif mime in (
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/msword",
        ) or fname.endswith((".docx", ".doc")):
            return _extract_docx(raw_bytes)
        elif mime.startswith("text/") or fname.endswith((".txt", ".csv", ".md", ".json", ".xml")):
            return _extract_text(raw_bytes)
        elif mime == "text/html" or fname.endswith(".html"):
            return _extract_text(raw_bytes)
        else:
            return ""
    except Exception:
        log.warning("document_parser.extract_failed", mime=mime, filename=filename, exc_info=True)
        return ""


def _extract_pdf(raw_bytes: bytes) -> str:
    from pypdf import PdfReader

    reader = PdfReader(io.BytesIO(raw_bytes))
    pages = []
    for i, page in enumerate(reader.pages):
        text = page.extract_text() or ""
        if text.strip():
            pages.append(f"[Page {i + 1}]\n{text.strip()}")
        if sum(len(p) for p in pages) > MAX_EXTRACTED_CHARS:
            break

    result = "\n\n".join(pages)
    if len(result) > MAX_EXTRACTED_CHARS:
        result = result[:MAX_EXTRACTED_CHARS] + "\n... [truncated]"
    return result


def _extract_docx(raw_bytes: bytes) -> str:
    from docx import Document

    doc = Document(io.BytesIO(raw_bytes))
    paragraphs = []
    total = 0
    for para in doc.paragraphs:
        text = para.text.strip()
        if text:
            paragraphs.append(text)
            total += len(text)
            if total > MAX_EXTRACTED_CHARS:
                break

    result = "\n".join(paragraphs)
    if len(result) > MAX_EXTRACTED_CHARS:
        result = result[:MAX_EXTRACTED_CHARS] + "\n... [truncated]"
    return result


def _extract_text(raw_bytes: bytes) -> str:
    text = raw_bytes.decode("utf-8", errors="replace")
    if len(text) > MAX_EXTRACTED_CHARS:
        text = text[:MAX_EXTRACTED_CHARS] + "\n... [truncated]"
    return text
