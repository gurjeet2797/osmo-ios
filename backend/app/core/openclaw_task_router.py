"""
openclaw_task_router.py — Decides when to delegate a user request to OpenClaw.

Three-tier hybrid routing:
  Tier 1 — Hard local-only (regex, instant): device controls, single calendar ops, etc.
  Tier 2 — Hard delegation (regex, instant): research, planning, analysis, reviews.
  Tier 3 — LLM classifier (only for ambiguous >5-word messages): cheap model, 2s timeout.
"""

from __future__ import annotations

import logging
import re
import time
from typing import Any

from app.config import settings

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Tier 1 — Always local (never delegate)
# ---------------------------------------------------------------------------
_LOCAL_ONLY_PATTERNS: list[re.Pattern[str]] = [
    re.compile(p, re.IGNORECASE)
    for p in [
        # Music / media controls
        r"\b(play|pause|skip|stop|resume|next|previous) (music|song|track|podcast|video|audio)\b",
        r"\bvolume (up|down|mute)\b",
        # Communication (simple)
        r"\b(call|text|message) \w+\b",
        r"\bsend (a )?(text|message|sms) to\b",
        # Timers & alarms
        r"\b(set|start|stop|cancel) (a )?(timer|alarm|stopwatch)\b",
        r"\bwake me (up )?(at|in)\b",
        # Device controls
        r"\b(turn|switch) (on|off)\b",
        r"\b(open|close|launch) (the )?(app|camera|settings|maps)\b",
        r"\btake (a )?(photo|picture|screenshot|selfie)\b",
        r"\bsend (a )?photo\b",
        r"\bflashlight\b",
        r"\bbrightness\b",
        r"\bdo not disturb\b",
        r"\bairplane mode\b",
        r"\bbluetooth\b",
        r"\bwi-?fi\b",
        # Single calendar operations (create/show/list — not review/analyze)
        r"\b(create|add|schedule|book) (a |an )?(event|meeting|appointment|reminder)\b",
        r"\b(show|list|what('s| is)) (my )?(calendar|events|schedule|meetings)\b",
        r"\bwhat do I have (today|tomorrow|this week)\b",
        r"\bam I free (at|on|this|tomorrow)\b",
        # Navigation (simple)
        r"\b(navigate|directions|how do I get) to\b",
        r"\btake me to\b",
        # Translation (simple)
        r"\b(translate|say) .{1,40} in (spanish|french|german|chinese|japanese|korean|italian|portuguese)\b",
        r"\bhow do you say\b",
        # Weather (simple)
        r"\b(what('s| is) the )?weather\b",
        r"\bis it (going to )?(rain|snow|hot|cold)\b",
        # Simple greetings / small talk
        r"^(hi|hey|hello|good morning|good night|thanks|thank you|ok|okay|sure|yes|no|bye|goodbye)\s*[!?.]?$",
    ]
]

# ---------------------------------------------------------------------------
# Tier 2 — Always delegate to OpenClaw
# ---------------------------------------------------------------------------
_DELEGATION_PATTERNS: list[re.Pattern[str]] = [
    re.compile(p, re.IGNORECASE)
    for p in [
        # Memory / persistence
        r"\bremind me\b",
        r"\bcheck (back|on|later)\b",
        r"\bfollow[- ]up\b",
        r"\bkeep track\b",
        r"\bremember (that|this|to)\b",
        # Briefing / prep
        r"\bprepare (a |my |for )\b",
        r"\bmorning briefing\b",
        r"\bprepare a briefing\b",
        r"\bmeeting prep\b",
        r"\bagenda for\b",
        # Research / investigation
        r"\bresearch\b",
        r"\bfind out\b",
        r"\binvestigate\b",
        r"\bbackground on\b",
        r"\bdeep dive\b",
        r"\bwho (is|are|was|were)\b",
        r"\bwhat do (I|you) know about\b",
        r"\bhistory of\b",
        # Drafting / summarization
        r"\bdraft (an?|the|my)\b",
        r"\bsummarize\b",
        r"\bwrite (an?|the|my) (essay|report|email|letter|proposal|plan|document)\b",
        # Thinking / planning / deciding
        r"\bhelp me (think|decide|plan|figure|choose|evaluate|prioritize)\b",
        r"\bpros and cons\b",
        r"\bstep by step\b",
        r"\bbreak (it |this )?down\b",
        r"\bwhat should I\b",
        r"\bshould I\b.*\bor\b",
        # Analysis
        r"\banalyze\b",
        r"\bcompare\b",
        r"\boptimize\b",
        r"\bevaluate\b",
        r"\bassess\b",
        r"\breflect\b",
        # Reviews / retrospectives
        r"\b(weekly|daily|monthly) review\b",
        r"\breview (my|the|this) (week|day|month|quarter)\b",
        r"\baction items\b",
        r"\bretro(spective)?\b",
        # Project / strategy
        r"\bstrategy\b",
        r"\bplan (for|out|a|my|the)\b",
        r"\bproject plan\b",
        r"\broadmap\b",
        r"\blong[- ]term\b",
        r"\bover (the )?(next|last|past)\b",
        r"\bmy preferences?\b",
        # Explicit complexity markers
        r"\bin detail\b",
        r"\bthoroughly\b",
        r"\bcomprehensive\b",
    ]
]


def _count_words(text: str) -> int:
    """Count words in the message."""
    return len(text.split())


def _count_steps(text: str) -> int:
    """Rough count of requested steps (comma/and/then separators)."""
    return (
        len(re.findall(r"\band\b", text, re.IGNORECASE))
        + len(re.findall(r"\bthen\b", text, re.IGNORECASE))
        + text.count(",")
    )


def _get_classifier_model() -> str:
    """Determine the cheap classifier model based on configured LLM provider."""
    if settings.openclaw_router_model:
        return settings.openclaw_router_model
    if settings.llm_provider == "anthropic":
        return "claude-haiku-4-5-20251001"
    return "gpt-4o-mini"


async def _llm_classify(user_message: str) -> bool:
    """
    Tier 3: Use a cheap LLM to classify ambiguous messages.
    Returns True if the message should be delegated to OpenClaw.
    Fails safe to False (local) on any error or timeout.
    """
    import httpx

    model = _get_classifier_model()
    prompt = (
        "You are a task router. Classify the following user message as either "
        "LOCAL (simple device action, quick lookup, single calendar op, small talk) "
        "or DELEGATE (needs research, analysis, multi-step planning, deep thinking, "
        "writing, or memory).\n\n"
        f"Message: \"{user_message}\"\n\n"
        "Respond with exactly one word: LOCAL or DELEGATE"
    )

    try:
        if "claude" in model or "haiku" in model:
            # Anthropic
            if not settings.anthropic_api_key:
                return False
            async with httpx.AsyncClient(timeout=httpx.Timeout(2.0)) as client:
                resp = await client.post(
                    "https://api.anthropic.com/v1/messages",
                    headers={
                        "x-api-key": settings.anthropic_api_key,
                        "anthropic-version": "2023-06-01",
                        "content-type": "application/json",
                    },
                    json={
                        "model": model,
                        "max_tokens": 10,
                        "messages": [{"role": "user", "content": prompt}],
                    },
                )
                resp.raise_for_status()
                text = resp.json()["content"][0]["text"].strip().upper()
        else:
            # OpenAI
            if not settings.openai_api_key:
                return False
            async with httpx.AsyncClient(timeout=httpx.Timeout(2.0)) as client:
                resp = await client.post(
                    "https://api.openai.com/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {settings.openai_api_key}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": model,
                        "max_tokens": 10,
                        "messages": [
                            {"role": "system", "content": "Respond with exactly one word."},
                            {"role": "user", "content": prompt},
                        ],
                    },
                )
                resp.raise_for_status()
                text = resp.json()["choices"][0]["message"]["content"].strip().upper()

        result = "DELEGATE" in text
        logger.info(
            "openclaw.router.llm_classify model=%s result=%s message=%s",
            model, "DELEGATE" if result else "LOCAL", user_message[:60],
        )
        return result

    except Exception as exc:  # noqa: BLE001
        logger.warning("openclaw.router.llm_classify_failed error=%s — defaulting to LOCAL", exc)
        return False


async def should_delegate_to_openclaw(
    user_message: str,
    context: dict[str, Any] | None = None,  # noqa: ARG001 — reserved for future use
) -> tuple[bool, str]:
    """
    Return (should_delegate, tier) indicating whether this request should be
    handled by OpenClaw rather than the local single-shot planner.

    Tiers:
      "tier1_local" — matched a local-only pattern, not delegated
      "tier2_delegate" — matched a delegation pattern, delegated
      "tier2_complexity" — multi-step complexity detected, delegated
      "tier3_llm" — LLM classifier decided
      "tier3_local_default" — no match, defaulted to local
    """
    start = time.monotonic()

    # Tier 1: hard local-only actions
    for pattern in _LOCAL_ONLY_PATTERNS:
        if pattern.search(user_message):
            _log_routing(False, "tier1_local", time.monotonic() - start, user_message)
            return False, "tier1_local"

    # Tier 2: hard delegation signals
    for pattern in _DELEGATION_PATTERNS:
        if pattern.search(user_message):
            _log_routing(True, "tier2_delegate", time.monotonic() - start, user_message)
            return True, "tier2_delegate"

    # Tier 2b: implicit multi-step complexity
    if _count_steps(user_message) >= 3:
        _log_routing(True, "tier2_complexity", time.monotonic() - start, user_message)
        return True, "tier2_complexity"

    # Tier 3: LLM classifier for ambiguous messages >5 words
    if _count_words(user_message) > 5:
        result = await _llm_classify(user_message)
        tier = "tier3_llm"
        _log_routing(result, tier, time.monotonic() - start, user_message)
        return result, tier

    # Default: local
    _log_routing(False, "tier3_local_default", time.monotonic() - start, user_message)
    return False, "tier3_local_default"


def _log_routing(delegated: bool, tier: str, latency: float, message: str) -> None:
    """Structured log for every routing decision."""
    logger.info(
        "openclaw.router decision=%s tier=%s latency_ms=%.1f message=%s",
        "DELEGATE" if delegated else "LOCAL",
        tier,
        latency * 1000,
        message[:80],
    )
