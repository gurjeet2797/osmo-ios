"""Automatic fact extraction from tool results.

After each command, scans tool results (emails, calendar events, etc.) and
extracts structured facts about contacts, locations, and patterns. These are
stored in the user's knowledge base for future context.
"""

from __future__ import annotations

import re
from typing import Any

import structlog

from app.core.knowledge import KnowledgeManager

log = structlog.get_logger()


async def extract_facts_from_results(
    km: KnowledgeManager,
    step_results: list[Any],
) -> int:
    """Scan step results and store extracted facts. Returns count of new facts."""
    facts: list[dict[str, Any]] = []

    for sr in step_results:
        if not sr.success or not sr.result:
            continue

        tool = sr.step.tool_name

        if tool == "google_gmail.search_emails":
            facts.extend(_extract_from_email_search(sr.result))
        elif tool == "google_gmail.read_email":
            facts.extend(_extract_from_email_read(sr.result))
        elif tool in ("google_calendar.list_events", "google_calendar.get_event"):
            facts.extend(_extract_from_calendar(sr.result))
        elif tool == "google_calendar.create_event":
            facts.extend(_extract_from_calendar_create(sr.result))

    if not facts:
        return 0

    # Deduplicate within this batch
    seen = set()
    unique: list[dict[str, Any]] = []
    for f in facts:
        if f["key"] not in seen:
            seen.add(f["key"])
            unique.append(f)

    try:
        return await km.store_many(unique)
    except Exception:
        log.warning("fact_extractor.store_failed", exc_info=True)
        return 0


def _extract_from_email_search(result: dict) -> list[dict[str, Any]]:
    """Extract contact facts from email search results."""
    facts = []
    messages = result.get("messages", [])
    for msg in messages:
        sender = msg.get("from", "")
        if sender:
            name, email = _parse_email_sender(sender)
            if name and email:
                key = f"contact:{_slugify(name)}:email"
                facts.append({
                    "key": key,
                    "value": f"{name} <{email}>",
                    "category": "contact",
                    "source": "extracted",
                    "confidence": 0.9,
                })
    return facts


def _extract_from_email_read(result: dict) -> list[dict[str, Any]]:
    """Extract facts from a full email body — addresses, phone numbers, etc."""
    facts = []
    body = result.get("body", "") or ""
    sender = result.get("from", "")
    subject = result.get("subject", "")

    # Extract sender contact
    if sender:
        name, email = _parse_email_sender(sender)
        if name and email:
            facts.append({
                "key": f"contact:{_slugify(name)}:email",
                "value": f"{name} <{email}>",
                "category": "contact",
                "source": "extracted",
                "confidence": 0.9,
            })

    # Extract phone numbers from body
    phones = _extract_phones(body)
    if phones and sender:
        name, _ = _parse_email_sender(sender)
        if name:
            for i, phone in enumerate(phones[:2]):  # max 2 per email
                suffix = "" if i == 0 else f"_{i+1}"
                facts.append({
                    "key": f"contact:{_slugify(name)}:phone{suffix}",
                    "value": phone,
                    "category": "contact",
                    "source": "extracted",
                    "confidence": 0.7,
                })

    # Extract street addresses from body
    addresses = _extract_addresses(body)
    if addresses and sender:
        name, _ = _parse_email_sender(sender)
        if name:
            for i, addr in enumerate(addresses[:2]):
                suffix = "" if i == 0 else f"_{i+1}"
                facts.append({
                    "key": f"contact:{_slugify(name)}:address{suffix}",
                    "value": addr,
                    "category": "contact",
                    "source": "extracted",
                    "confidence": 0.7,
                })

    return facts


def _extract_from_calendar(result: dict) -> list[dict[str, Any]]:
    """Extract contact facts from calendar events (attendees)."""
    facts = []
    events = result.get("events", [])
    if not events and "id" in result:
        events = [result]  # single event from get_event
    for event in events:
        for att in event.get("attendees", []):
            email = att.get("email", "")
            name = att.get("displayName", "")
            if email and name:
                facts.append({
                    "key": f"contact:{_slugify(name)}:email",
                    "value": f"{name} <{email}>",
                    "category": "contact",
                    "source": "extracted",
                    "confidence": 0.85,
                })
    return facts


def _extract_from_calendar_create(result: dict) -> list[dict[str, Any]]:
    """Extract facts from event creation — same as reading an event."""
    return _extract_from_calendar(result)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _parse_email_sender(sender: str) -> tuple[str, str]:
    """Parse 'John Doe <john@example.com>' into (name, email)."""
    match = re.match(r"^(.+?)\s*<(.+?)>$", sender.strip())
    if match:
        return match.group(1).strip().strip('"'), match.group(2).strip()
    # Plain email
    if "@" in sender:
        local = sender.split("@")[0]
        name = local.replace(".", " ").replace("_", " ").title()
        return name, sender.strip()
    return "", ""


def _slugify(name: str) -> str:
    """Convert a name to a slug for use as a key: 'Erica Humphrey' → 'erica_humphrey'."""
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def _extract_phones(text: str) -> list[str]:
    """Extract US phone numbers from text."""
    patterns = [
        r"\+?1?[-.\s]?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}",
    ]
    phones = []
    for p in patterns:
        for match in re.finditer(p, text):
            num = match.group().strip()
            # Filter out numbers that are too short or clearly not phones
            digits = re.sub(r"\D", "", num)
            if 10 <= len(digits) <= 11:
                phones.append(num)
    return phones


def _extract_addresses(text: str) -> list[str]:
    """Extract US street addresses from text (best-effort regex)."""
    # Match patterns like "123 Main St, Austin, TX 78701" or multi-line addresses
    pattern = r"\d{1,6}\s+[A-Z][a-zA-Z\s.]+(?:St|Ave|Blvd|Dr|Rd|Ln|Way|Ct|Pl|Pkwy|Cir|Ter|Loop|Trail|Highway|Hwy|Route|Rt)\.?(?:\s*(?:#|Apt|Suite|Ste|Unit|Bldg)\.?\s*\w+)?(?:\s*,\s*[A-Z][a-zA-Z\s]+)?(?:\s*,\s*[A-Z]{2}\s+\d{5}(?:-\d{4})?)?"
    addresses = []
    for match in re.finditer(pattern, text, re.IGNORECASE):
        addr = match.group().strip().rstrip(",")
        # Must have at least a city or zip to be meaningful
        if len(addr) > 15:
            addresses.append(addr)
    return addresses
