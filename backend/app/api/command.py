from __future__ import annotations

import json
import time
from typing import Annotated, Any

import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from datetime import UTC, datetime, timedelta

from sqlalchemy import func as sa_func, select

from app.config import settings
from app.connectors.google_calendar import credentials_from_encrypted
from app.tools.loader import discover_and_load_skills
from app.connectors.llm import LLMResponse, ToolCall, create_llm_client
from app.core.executor import Executor
from app.core.fact_extractor import extract_facts_from_results
from app.core.knowledge import KnowledgeManager
from app.core.planner import _from_api_name, _to_api_name, build_tools, build_system_prompt
from app.core.policy import evaluate
from app.core.preference_manager import PreferenceManager
from app.core.session_manager import SessionManager
from app.core.verifier import verify_device_result, verify_server_step
from app.db.session import get_db
from app.dependencies import get_current_user
from app.models.audit import AuditLog
from app.models.command_history import CommandHistory
from app.models.user import User
from app.schemas.action_plan import ActionPlan, ActionStep, RiskLevel
from app.schemas.command import (
    Attachment,
    CommandRequest,
    CommandResponse,
    ConfirmRequest,
    DeviceResultRequest,
)
from app.tools.base import ToolContext

log = structlog.get_logger()

discover_and_load_skills()

router = APIRouter()

# Pending plans with timestamp for TTL cleanup
_pending_plans: dict[str, tuple[ActionPlan, str, list[dict[str, Any]], float]] = {}
_PLAN_TTL_SECONDS = 600  # 10 minutes
MAX_TOOL_ITERATIONS = 10  # max follow-up tool call rounds per request
MAX_NARRATION_NUDGES = 2  # max times we'll nudge the LLM to stop narrating

# Phrases that indicate the LLM is narrating intent instead of delivering a final answer
_NARRATION_PATTERNS = (
    "let me search", "let me read", "let me check", "let me look",
    "let me find", "let me get", "i'll search", "i'll read", "i'll check",
    "i'll look", "i'll find", "i'll get", "i need to", "i should",
    "let me try", "let me see", "searching for", "looking up",
    "let me pull", "i'll pull",
)

_NARRATION_NUDGE = (
    "Do not narrate. You must either call a tool now or deliver the final answer "
    "with the specific information the user asked for. If you still need data, "
    "call the appropriate tool. If you have enough data, give the answer."
)


def _is_narration(text: str | None) -> bool:
    """Detect if the LLM is narrating its intent instead of delivering a final answer."""
    if not text:
        return False
    lower = text.strip().lower()
    # Ends with colon — setting up for something it didn't do
    if lower.endswith(":"):
        return True
    # Contains narration phrases
    return any(p in lower for p in _NARRATION_PATTERNS)

# Cached tool specs (rebuilt once per process)
_cached_tools: list[dict[str, Any]] | None = None


def _get_tools() -> list[dict[str, Any]]:
    """Return cached tool specs, building once per process."""
    global _cached_tools
    if _cached_tools is None:
        _cached_tools = build_tools()
    return _cached_tools


def _cleanup_expired_plans() -> None:
    """Remove plans older than TTL."""
    now = time.monotonic()
    expired = [pid for pid, (_, _, _, ts) in _pending_plans.items() if now - ts > _PLAN_TTL_SECONDS]
    for pid in expired:
        _pending_plans.pop(pid, None)
    if expired:
        log.info("plans.cleanup", expired_count=len(expired))


async def _count_today_commands(db: AsyncSession, user_id: str) -> int:
    """Count how many commands this user has sent today."""
    today_start = datetime.now(UTC).replace(hour=0, minute=0, second=0, microsecond=0)
    result = await db.execute(
        select(sa_func.count(CommandHistory.id))
        .where(CommandHistory.user_id == user_id)
        .where(CommandHistory.created_at >= today_start)
    )
    return result.scalar_one()


def _get_user_tier(user: User) -> str:
    """Determine effective subscription tier (dev emails override)."""
    dev_emails = [e.strip() for e in settings.dev_emails.split(",") if e.strip()]
    if user.email in dev_emails:
        return "dev"
    return user.subscription_tier or "free"


def _extract_updated_name(step_results: list) -> str | None:
    """Scan step results for a user_profile.set_name result and return the updated name."""
    for sr in step_results:
        if sr.success and sr.result and sr.step.tool_name == "user_profile.set_name":
            return sr.result.get("updated_name")
    return None


def _extract_attachments(step_results: list) -> list[Attachment]:
    """Scan executor step results for attachment data returned by gmail tools."""
    attachments: list[Attachment] = []
    for sr in step_results:
        if not sr.success or not sr.result:
            continue
        # get_attachment returns {id, filename, mime_type, size, url}
        if sr.step.tool_name == "google_gmail.get_attachment":
            r = sr.result
            if all(k in r for k in ("id", "filename", "mime_type", "url", "size")):
                attachments.append(Attachment(
                    id=r["id"],
                    filename=r["filename"],
                    mime_type=r["mime_type"],
                    url=r["url"],
                    size=r["size"],
                ))
    return attachments


def _build_context(
    user: User,
    db: AsyncSession | None = None,
    latitude: float | None = None,
    longitude: float | None = None,
) -> ToolContext:
    google_creds = None
    if user.google_tokens_encrypted:
        google_creds = credentials_from_encrypted(user.google_tokens_encrypted)
    return ToolContext(
        user_id=str(user.id),
        google_credentials=google_creds,
        timezone=user.timezone,
        db=db,
        latitude=latitude,
        longitude=longitude,
    )


def _tool_calls_to_steps(tool_calls: list[ToolCall]) -> list[ActionStep]:
    """Convert unified ToolCall objects into ActionStep objects."""
    steps = []
    for tc in tool_calls:
        name = tc.name  # already converted back to internal name by LLMResponse
        args = tc.arguments  # already a dict

        # Conservative risk defaults based on action type
        if "delete" in name or "cancel" in name:
            risk = RiskLevel.high
            confirm = True
            phrase = f"Delete/cancel via {name} — confirm?"
        elif "create" in name or "update" in name:
            risk = RiskLevel.medium
            confirm = "attendees" in args
            phrase = f"Modify via {name} — confirm?" if confirm else None
        else:
            risk = RiskLevel.low
            confirm = False
            phrase = None

        # Determine execution target from tool registry
        from app.tools.registry import get_tool
        tool = get_tool(name)
        target = tool.execution_target if tool else "server"

        steps.append(
            ActionStep(
                tool_name=name,
                args=args,
                risk_level=risk,
                requires_confirmation=confirm,
                confirmation_phrase=phrase,
                execution_target=target,
                tool_call_id=tc.id,
            )
        )
    return steps


def _build_anthropic_result_blocks(
    tool_calls: list[ToolCall], step_results: list,
) -> list[dict[str, Any]]:
    """Build Anthropic tool_result content blocks from tool calls and their results."""
    blocks: list[dict[str, Any]] = []
    for tc, sr in zip(tool_calls, step_results):
        if sr.success:
            content = json.dumps(sr.result) if sr.result else '{"status": "ok"}'
        else:
            content = json.dumps({"error": sr.error or "unknown error"})
        blocks.append({
            "type": "tool_result",
            "tool_use_id": tc.id,
            "content": content,
        })
    return blocks


async def _tool_use_loop(
    llm: Any,
    system_prompt: str,
    session_messages: list[dict[str, Any]],
    tool_calls: list[ToolCall],
    step_results: list,
    tools: list[dict[str, Any]],
    context: ToolContext,
    plan_id: str,
    user_id: str,
    transcript: str,
    timezone: str,
    locale: str,
    db: AsyncSession,
    use_anthropic: bool,
) -> tuple[str, list[dict[str, Any]], list, list]:
    """Execute tools → send results to LLM → if LLM calls more tools → repeat.

    Includes narration detection: if the LLM responds with text that narrates
    intent ("Let me read...", ends with ":") instead of delivering a final answer
    or calling tools, we nudge it to either call a tool or give the answer.

    Returns (spoken_text, session_messages, all_step_results, new_device_actions).
    """
    all_step_results = list(step_results)
    all_device_actions: list = []
    current_tool_calls = tool_calls
    current_step_results = step_results
    spoken = "Done."
    follow_up = None
    narration_nudges = 0

    for _iteration in range(MAX_TOOL_ITERATIONS):
        # Append tool results to session
        if use_anthropic:
            result_blocks = _build_anthropic_result_blocks(current_tool_calls, current_step_results)
            SessionManager.append_tool_results(session_messages, result_blocks)
        else:
            SessionManager.append_openai_tool_results(
                session_messages, current_tool_calls, current_step_results,
            )

        # Ask LLM to continue (with tools so it can call more)
        follow_up = await llm.follow_up(system_prompt, session_messages, tools=tools)

        # Append assistant response to session
        if use_anthropic:
            SessionManager.append_assistant_response(session_messages, follow_up)
        else:
            SessionManager.append_openai_assistant_response(session_messages, follow_up)

        # No more tool calls — check if this is a real answer or narration
        if not follow_up.tool_calls:
            if _is_narration(follow_up.text) and narration_nudges < MAX_NARRATION_NUDGES:
                # LLM narrated instead of acting — nudge it to execute or answer
                narration_nudges += 1
                log.warning(
                    "tool_loop.narration_detected",
                    iteration=_iteration + 1,
                    nudge=narration_nudges,
                    text=follow_up.text[:120] if follow_up.text else None,
                )
                # Send nudge as user message to push LLM back into tool-calling mode
                if use_anthropic:
                    session_messages.append({"role": "user", "content": _NARRATION_NUDGE})
                else:
                    session_messages.append({"role": "user", "content": _NARRATION_NUDGE})

                # Re-ask with same tools available — use a synthetic empty tool call list
                # to re-enter the loop (the LLM should now call tools or give the answer)
                nudge_response = await llm.follow_up(system_prompt, session_messages, tools=tools)

                if use_anthropic:
                    SessionManager.append_assistant_response(session_messages, nudge_response)
                else:
                    SessionManager.append_openai_assistant_response(session_messages, nudge_response)

                if nudge_response.tool_calls:
                    # LLM recovered — execute the tools and continue the loop
                    follow_up = nudge_response
                    log.info(
                        "tool_loop.narration_recovered",
                        tools=[tc.name for tc in follow_up.tool_calls],
                    )
                else:
                    # Still no tools — accept whatever text we got
                    spoken = nudge_response.text or follow_up.text or "Done."
                    break
            else:
                spoken = follow_up.text or "Done."
                break

        if not follow_up.tool_calls:
            break

        # Execute follow-up tool calls
        log.info(
            "tool_loop.iteration",
            iteration=_iteration + 1,
            tools=[tc.name for tc in follow_up.tool_calls],
        )
        new_steps = _tool_calls_to_steps(follow_up.tool_calls)
        new_plan = ActionPlan(
            user_intent=transcript, timezone=timezone, locale=locale, steps=new_steps,
        )
        executor = Executor()
        new_exec = await executor.execute_confirmed_plan(new_plan, context)

        for sr in new_exec.step_results:
            if sr.success and sr.result and sr.step.execution_target == "server":
                await verify_server_step(sr.step.tool_name, sr.step.args, sr.result, context)
            await _audit(
                db, user_id, plan_id,
                sr.step.tool_name, sr.step.args, sr.result,
                "ok" if sr.success else "error", sr.error,
            )

        all_step_results.extend(new_exec.step_results)
        all_device_actions.extend(new_exec.device_actions)
        current_tool_calls = follow_up.tool_calls
        current_step_results = new_exec.step_results
    else:
        # Max iterations reached — use whatever text the LLM last produced
        if follow_up and follow_up.text:
            spoken = follow_up.text

    return spoken, session_messages, all_step_results, all_device_actions


async def _audit(
    db: AsyncSession,
    user_id: str,
    plan_id: str,
    tool_name: str,
    args: dict,
    result: dict | None,
    stat: str,
    error: str | None = None,
) -> None:
    entry = AuditLog(
        user_id=user_id,
        plan_id=plan_id,
        tool_name=tool_name,
        args=args,
        result=result,
        status=stat,
        error=error,
    )
    db.add(entry)
    await db.commit()


async def _record_command(
    db: AsyncSession,
    user: User,
    body: CommandRequest,
    tool_names: list[str],
) -> None:
    """Record a command to history for pattern analysis (best-effort)."""
    try:
        now = datetime.now(UTC)
        entry = CommandHistory(
            user_id=str(user.id),
            transcript=body.transcript,
            tool_names=tool_names if tool_names else None,
            latitude=body.latitude,
            longitude=body.longitude,
            hour_of_day=now.hour,
            day_of_week=now.weekday(),
        )
        db.add(entry)
        await db.commit()
    except Exception:
        log.warning("command_history.record_failed", exc_info=True)


@router.post("", response_model=CommandResponse)
async def handle_command(
    body: CommandRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    # Rate limiting
    tier = _get_user_tier(user)
    remaining_requests: int | None = None
    if tier == "free":
        cmd_count = await _count_today_commands(db, str(user.id))
        remaining_requests = max(0, settings.free_daily_limit - cmd_count)
        if remaining_requests <= 0:
            return CommandResponse(
                spoken_response=f"You've hit your daily limit of {settings.free_daily_limit} requests. Upgrade to Pro for unlimited access.",
                remaining_requests=0,
            )
        remaining_requests -= 1  # account for this request

    llm = create_llm_client()
    providers = body.linked_providers or ["google_calendar"]

    # Load user preferences and knowledge facts for system prompt context
    pref_mgr = PreferenceManager(db, str(user.id))
    km = KnowledgeManager(db, str(user.id))
    prefs = await pref_mgr.get_all()
    try:
        facts = await km.get_all()
    except Exception:
        log.debug("knowledge.load_failed", exc_info=True)
        facts = []
    pref_block = PreferenceManager.build_context_block(prefs)
    knowledge_block = KnowledgeManager.build_context_block(facts)

    # Combine preference and knowledge blocks
    user_context = "\n\n".join(filter(None, [pref_block, knowledge_block]))

    system_prompt = build_system_prompt(
        body.timezone, body.locale, providers,
        latitude=body.latitude, longitude=body.longitude,
        user_preferences=user_context,
    )
    tools = _get_tools()
    use_anthropic = settings.llm_provider == "anthropic"

    # Cleanup expired pending plans on each request
    _cleanup_expired_plans()

    # 1. Load session history (both providers now use sessions)
    sm = SessionManager(db, str(user.id))
    session_messages = await sm.load()

    # 2. Ask the LLM (with session recovery and graceful error handling)
    try:
        response = await llm.chat(
            system_prompt,
            body.transcript,
            tools,
            messages=session_messages,
            image_data=body.image_data,
        )
    except Exception as chat_err:
        err_str = str(chat_err)
        # If session history is corrupted (e.g. dangling tool_use without tool_result),
        # clear it and retry with a fresh session.
        if "tool_use" in err_str or "tool_call" in err_str:
            log.warning("session.corrupted, clearing and retrying", error=err_str)
            await sm.clear()
            session_messages = []
            try:
                response = await llm.chat(
                    system_prompt,
                    body.transcript,
                    tools,
                    messages=session_messages,
                    image_data=body.image_data,
                )
            except Exception:
                log.exception("llm.retry_failed")
                return CommandResponse(
                    spoken_response="I'm having trouble connecting right now. Please try again in a moment.",
                    remaining_requests=remaining_requests,
                )
        else:
            log.exception("llm.chat_failed")
            return CommandResponse(
                spoken_response="Something went wrong on my end. Please try again.",
                remaining_requests=remaining_requests,
            )

    # Track messages for session persistence
    if use_anthropic:
        SessionManager.append_user_message(session_messages, body.transcript)
        SessionManager.append_assistant_response(session_messages, response)
    else:
        SessionManager.append_openai_user_message(session_messages, body.transcript)
        SessionManager.append_openai_assistant_response(session_messages, response)

    # 3. No tool calls — check for narration before accepting as final answer
    if not response.tool_calls:
        # If the LLM narrated instead of calling tools, nudge it once
        if _is_narration(response.text):
            log.warning("initial.narration_detected", text=response.text[:120] if response.text else None)
            if use_anthropic:
                session_messages.append({"role": "user", "content": _NARRATION_NUDGE})
            else:
                session_messages.append({"role": "user", "content": _NARRATION_NUDGE})

            nudge_resp = await llm.follow_up(system_prompt, session_messages, tools=tools)
            if use_anthropic:
                SessionManager.append_assistant_response(session_messages, nudge_resp)
            else:
                SessionManager.append_openai_assistant_response(session_messages, nudge_resp)

            if nudge_resp.tool_calls:
                # Recovered — use this as the response and continue to tool execution
                response = nudge_resp
            else:
                # Accept the nudge response as final
                await sm.save(session_messages)
                await _record_command(db, user, body, [])
                return CommandResponse(
                    spoken_response=nudge_resp.text or response.text or "I'm here. What can I help with?",
                    requires_confirmation=False,
                    remaining_requests=remaining_requests,
                )
        else:
            await sm.save(session_messages)
            await _record_command(db, user, body, [])
            return CommandResponse(
                spoken_response=response.text or "I'm here. What can I help with?",
                requires_confirmation=False,
                remaining_requests=remaining_requests,
            )

    # 4. Convert tool calls to ActionSteps → ActionPlan
    steps = _tool_calls_to_steps(response.tool_calls)
    plan = ActionPlan(
        user_intent=body.transcript,
        timezone=body.timezone,
        locale=body.locale,
        steps=steps,
    )

    # 5. Policy gate
    policy_result = evaluate(plan)
    if policy_result.blocked:
        await sm.save(session_messages)
        return CommandResponse(
            spoken_response=policy_result.block_reason or "This action is blocked by policy.",
            action_plan=plan,
            remaining_requests=remaining_requests,
        )

    # 6. Confirmation check
    if plan.needs_confirmation:
        _pending_plans[plan.plan_id] = (plan, str(user.id), session_messages, time.monotonic())

        phrases = [
            s.confirmation_phrase
            for s in plan.steps
            if s.requires_confirmation and s.confirmation_phrase
        ]
        prompt = " ".join(phrases) if phrases else f"Confirm: {plan.user_intent}?"

        await sm.save(session_messages)
        return CommandResponse(
            spoken_response=prompt,
            action_plan=plan,
            requires_confirmation=True,
            confirmation_prompt=prompt,
            plan_id=plan.plan_id,
            remaining_requests=remaining_requests,
        )

    # 7. Execute
    context = _build_context(user, db=db, latitude=body.latitude, longitude=body.longitude)
    executor = Executor()
    exec_result = await executor.execute_plan(plan, context)

    for sr in exec_result.step_results:
        if sr.success and sr.result and sr.step.execution_target == "server":
            await verify_server_step(sr.step.tool_name, sr.step.args, sr.result, context)

        await _audit(
            db, str(user.id), plan.plan_id,
            sr.step.tool_name, sr.step.args, sr.result,
            "ok" if sr.success else "error", sr.error,
        )

    # 8. Tool use loop — send results, let LLM call more tools until final answer
    spoken, session_messages, all_step_results, loop_device_actions = await _tool_use_loop(
        llm=llm,
        system_prompt=system_prompt,
        session_messages=session_messages,
        tool_calls=response.tool_calls,
        step_results=exec_result.step_results,
        tools=tools,
        context=context,
        plan_id=plan.plan_id,
        user_id=str(user.id),
        transcript=body.transcript,
        timezone=body.timezone,
        locale=body.locale,
        db=db,
        use_anthropic=use_anthropic,
    )
    exec_result.device_actions.extend(loop_device_actions)
    await sm.save(session_messages)

    attachments = _extract_attachments(all_step_results)
    updated_name = _extract_updated_name(all_step_results)

    # Record command history for pattern analysis
    await _record_command(db, user, body, [s.tool_name for s in plan.steps])

    # Background: extract and store facts from tool results (best-effort)
    try:
        new_facts = await extract_facts_from_results(km, all_step_results)
        if new_facts:
            log.info("facts.extracted", user_id=str(user.id), new_count=new_facts)
    except Exception:
        log.debug("facts.extraction_failed", exc_info=True)

    return CommandResponse(
        spoken_response=spoken,
        action_plan=plan,
        device_actions=exec_result.device_actions,
        plan_id=plan.plan_id,
        attachments=attachments,
        updated_user_name=updated_name,
        remaining_requests=remaining_requests,
    )


@router.post("/confirm", response_model=CommandResponse)
async def confirm_plan(
    body: ConfirmRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    entry = _pending_plans.pop(body.plan_id, None)
    if entry is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Plan not found or expired")

    plan, owner_id, session_messages, _created_at = entry
    if owner_id != str(user.id):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Plan belongs to another user")

    context = _build_context(user, db=db)
    executor = Executor()
    exec_result = await executor.execute_confirmed_plan(plan, context)

    for sr in exec_result.step_results:
        if sr.success and sr.result and sr.step.execution_target == "server":
            await verify_server_step(sr.step.tool_name, sr.step.args, sr.result, context)

        await _audit(
            db, str(user.id), plan.plan_id,
            sr.step.tool_name, sr.step.args, sr.result,
            "ok" if sr.success else "error", sr.error,
        )

    # Natural summary via LLM follow-up
    llm = create_llm_client()
    providers = ["google_calendar"]
    system_prompt = build_system_prompt(context.timezone, "en-US", providers)
    tools = _get_tools()
    use_anthropic = settings.llm_provider == "anthropic"

    # Reconstruct tool calls from plan steps
    synthetic_tool_calls = [
        ToolCall(
            id=step.tool_call_id or step.idempotency_key,
            name=step.tool_name,
            arguments=step.args,
        )
        for step in plan.steps
    ]

    sm = SessionManager(db, str(user.id))
    all_step_results = list(exec_result.step_results)
    if synthetic_tool_calls and exec_result.step_results:
        spoken, session_messages, all_step_results, loop_device_actions = await _tool_use_loop(
            llm=llm,
            system_prompt=system_prompt,
            session_messages=session_messages,
            tool_calls=synthetic_tool_calls,
            step_results=exec_result.step_results,
            tools=tools,
            context=context,
            plan_id=plan.plan_id,
            user_id=str(user.id),
            transcript=plan.user_intent,
            timezone=plan.timezone,
            locale=plan.locale,
            db=db,
            use_anthropic=use_anthropic,
        )
        exec_result.device_actions.extend(loop_device_actions)
        await sm.save(session_messages)
    else:
        parts = []
        for sr in exec_result.step_results:
            if sr.device_action:
                parts.append(f"Sending '{sr.step.tool_name}' to your device.")
            elif sr.success:
                parts.append(f"Done: {sr.step.tool_name}.")
            else:
                parts.append(f"Failed: {sr.step.tool_name} — {sr.error}")
        spoken = " ".join(parts) if parts else f"Done: {plan.user_intent}"

    attachments = _extract_attachments(all_step_results)
    updated_name = _extract_updated_name(all_step_results)

    # Extract facts from confirmed plan results
    try:
        km = KnowledgeManager(db, str(user.id))
        await extract_facts_from_results(km, all_step_results)
    except Exception:
        log.debug("facts.extraction_failed", exc_info=True)

    return CommandResponse(
        spoken_response=spoken,
        action_plan=plan,
        device_actions=exec_result.device_actions,
        plan_id=plan.plan_id,
        attachments=attachments,
        updated_user_name=updated_name,
    )


@router.get("/briefing")
async def get_briefing(
    user: Annotated[User, Depends(get_current_user)],
):
    from app.core.briefing import get_cached_briefing
    data = await get_cached_briefing(str(user.id))
    if data:
        return data
    return {"briefing": None, "generated_at": None}


@router.post("/session/clear")
async def clear_session(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    sm = SessionManager(db, str(user.id))
    await sm.clear()
    return {"status": "cleared"}


@router.post("/device-result")
async def report_device_result(
    body: DeviceResultRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    verifications = []
    for dr in body.results:
        v = verify_device_result(dr)
        verifications.append(
            {"action_id": dr.action_id, "matched": v.matched, "discrepancies": v.discrepancies}
        )

        await _audit(
            db,
            str(user.id),
            body.plan_id,
            f"device:{dr.action_id}",
            {},
            dr.result,
            "ok" if dr.success else "error",
            dr.error,
        )

    all_ok = all(v["matched"] for v in verifications)
    return {
        "status": "verified" if all_ok else "partial_failure",
        "verifications": verifications,
    }
