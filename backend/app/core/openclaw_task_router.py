"""
openclaw_task_router.py — Decides when to delegate a user request to OpenClaw.

Simple heuristic router. No extra LLM call needed — keyword + complexity
signals are sufficient. The goal is to keep snappy one-shot device actions
(play music, add calendar event) local, and send multi-step, research, memory,
or briefing tasks to the OpenClaw agent.
"""

from __future__ import annotations

import re
from typing import Any

# ---------------------------------------------------------------------------
# Signals that suggest an OpenClaw delegation is appropriate
# ---------------------------------------------------------------------------

# Phrases that imply persistence, background work, or research
_DELEGATION_PATTERNS: list[re.Pattern[str]] = [
    re.compile(p, re.IGNORECASE)
    for p in [
        r"\bremind me\b",
        r"\bcheck (back|on|later)\b",
        r"\bfollow[- ]up\b",
        r"\bkeep track\b",
        r"\bremember (that|this|to)\b",
        r"\bprepare a briefing\b",
        r"\bmorning briefing\b",
        r"\bdraft (an?|the)\b",
        r"\bsummarize\b",
        r"\bresearch\b",
        r"\bwho (is|are|was)\b",
        r"\bfind out\b",
        r"\binvestigate\b",
        r"\bbackground on\b",
        r"\bmeeting prep\b",
        r"\bagenda for\b",
        r"\bwhat do (I|you) know about\b",
        r"\bmy preferences?\b",
        r"\bstrategy\b",
        r"\bplan (for|out|a)\b",
        r"\banalyze\b",
        r"\bcompare\b",
        r"\bover (the )?(next|last|past)\b",
        r"\bhistory of\b",
        r"\blong[- ]term\b",
    ]
]

# Simple device actions that should always stay local (never delegate)
_LOCAL_ONLY_PATTERNS: list[re.Pattern[str]] = [
    re.compile(p, re.IGNORECASE)
    for p in [
        r"\b(play|pause|skip|stop) (music|song|track|podcast)\b",
        r"\b(call|text|message) \w+\b",
        r"\b(set|start|stop) (a )?timer\b",
        r"\b(turn|switch) (on|off)\b",
        r"\bopen (the )?app\b",
        r"\btake (a )?photo\b",
        r"\bsend (a )?photo\b",
        r"\blaunch\b",
        r"\bvolume (up|down)\b",
    ]
]


def _count_steps(text: str) -> int:
    """Rough count of requested steps (comma/and/then separators)."""
    return (
        len(re.findall(r"\band\b", text, re.IGNORECASE))
        + len(re.findall(r"\bthen\b", text, re.IGNORECASE))
        + text.count(",")
    )


async def should_delegate_to_openclaw(
    user_message: str,
    context: dict[str, Any] | None = None,  # noqa: ARG001 — reserved for future use
) -> bool:
    """
    Return True if this request should be handled by OpenClaw rather than
    the local single-shot planner.

    Rules (in priority order):
    1. If it matches a local-only pattern → always False
    2. If it matches a delegation pattern → True
    3. If the message is clearly multi-step (3+ conjunctions/commas) → True
    4. Otherwise → False (local planner handles it)
    """
    # Rule 1: hard local-only actions
    for pattern in _LOCAL_ONLY_PATTERNS:
        if pattern.search(user_message):
            return False

    # Rule 2: explicit delegation signals
    for pattern in _DELEGATION_PATTERNS:
        if pattern.search(user_message):
            return True

    # Rule 3: implicit multi-step complexity
    if _count_steps(user_message) >= 3:
        return True

    return False
