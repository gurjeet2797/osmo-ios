from __future__ import annotations

import json
from typing import Annotated, Any

import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.connectors.google_calendar import credentials_from_encrypted
from app.tools.loader import discover_and_load_skills
from app.connectors.llm import LLMResponse, ToolCall, create_llm_client
from app.core.executor import Executor
from app.core.planner import _from_api_name, _to_api_name, build_tools, build_system_prompt
from app.core.policy import evaluate
from app.core.session_manager import SessionManager
from app.core.verifier import verify_device_result, verify_server_step
from app.db.session import get_db
from app.dependencies import get_current_user
from app.models.audit import AuditLog
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

_pending_plans: dict[str, tuple[ActionPlan, str, list[dict[str, Any]]]] = {}


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


def _build_context(user: User, db: AsyncSession | None = None) -> ToolContext:
    google_creds = None
    if user.google_tokens_encrypted:
        google_creds = credentials_from_encrypted(user.google_tokens_encrypted)
    return ToolContext(
        user_id=str(user.id),
        google_credentials=google_creds,
        timezone=user.timezone,
        db=db,
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


async def _llm_summarize_anthropic(
    llm: Any,
    system_prompt: str,
    session_messages: list[dict[str, Any]],
    tool_calls: list[ToolCall],
    step_results: list,
    tools: list[dict[str, Any]],
) -> tuple[str, list[dict[str, Any]]]:
    """Send tool results back to LLM via Anthropic format and return summary + updated messages."""
    # Build tool_result blocks
    result_blocks: list[dict[str, Any]] = []
    for tc, sr in zip(tool_calls, step_results):
        if sr.success:
            content = json.dumps(sr.result) if sr.result else '{"status": "ok"}'
        else:
            content = json.dumps({"error": sr.error or "unknown error"})
        result_blocks.append(
            {
                "type": "tool_result",
                "tool_use_id": tc.id,
                "content": content,
            }
        )

    # Append tool results as a user message
    SessionManager.append_tool_results(session_messages, result_blocks)

    # Follow up for natural summary
    follow_up = await llm.follow_up(system_prompt, session_messages, tools=tools)

    # Append assistant response to session
    SessionManager.append_assistant_response(session_messages, follow_up)

    return follow_up.text or "Done.", session_messages


async def _llm_summarize_openai(
    llm: Any,
    system_prompt: str,
    user_message: str,
    tool_calls: list[ToolCall],
    step_results: list,
    tools: list[dict[str, Any]],
) -> str:
    """Send tool results back to LLM via OpenAI format for summary."""
    messages: list[dict[str, Any]] = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_message},
    ]

    # The assistant's response that contained tool_calls
    messages.append(
        {
            "role": "assistant",
            "content": None,
            "tool_calls": [
                {
                    "id": tc.id,
                    "type": "function",
                    "function": {
                        "name": _to_api_name(tc.name),
                        "arguments": json.dumps(tc.arguments),
                    },
                }
                for tc in tool_calls
            ],
        }
    )

    # Tool results
    for tc, sr in zip(tool_calls, step_results):
        if sr.success:
            content = json.dumps(sr.result) if sr.result else '{"status": "ok"}'
        else:
            content = json.dumps({"error": sr.error or "unknown error"})
        messages.append(
            {
                "role": "tool",
                "tool_call_id": tc.id,
                "content": content,
            }
        )

    follow_up = await llm.follow_up(system_prompt, messages, tools=tools)
    return follow_up.text or "Done."


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


@router.post("", response_model=CommandResponse)
async def handle_command(
    body: CommandRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    llm = create_llm_client()
    providers = body.linked_providers or ["google_calendar"]
    system_prompt = build_system_prompt(body.timezone, body.locale, providers)
    tools = build_tools()
    use_anthropic = settings.llm_provider == "anthropic"

    # 1. Load session history (Anthropic) or start fresh (OpenAI)
    session_messages: list[dict[str, Any]] = []
    sm: SessionManager | None = None
    if use_anthropic:
        sm = SessionManager(db, str(user.id))
        session_messages = await sm.load()

    # 2. Ask the LLM
    response = await llm.chat(
        system_prompt,
        body.transcript,
        tools,
        messages=session_messages if use_anthropic else None,
    )

    # Track messages for session persistence
    if use_anthropic:
        SessionManager.append_user_message(session_messages, body.transcript)
        SessionManager.append_assistant_response(session_messages, response)

    # 3. No tool calls → pure conversational response
    if not response.tool_calls:
        if sm:
            await sm.save(session_messages)
        return CommandResponse(
            spoken_response=response.text or "...",
            requires_confirmation=False,
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
        if sm:
            await sm.save(session_messages)
        return CommandResponse(
            spoken_response=policy_result.block_reason or "This action is blocked by policy.",
            action_plan=plan,
        )

    # 6. Confirmation check
    if plan.needs_confirmation:
        _pending_plans[plan.plan_id] = (plan, str(user.id), session_messages)

        phrases = [
            s.confirmation_phrase
            for s in plan.steps
            if s.requires_confirmation and s.confirmation_phrase
        ]
        prompt = " ".join(phrases) if phrases else f"Confirm: {plan.user_intent}?"

        if sm:
            await sm.save(session_messages)
        return CommandResponse(
            spoken_response=prompt,
            action_plan=plan,
            requires_confirmation=True,
            confirmation_prompt=prompt,
            plan_id=plan.plan_id,
        )

    # 7. Execute
    context = _build_context(user, db=db)
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

    # 8. LLM follow-up for natural summary
    if use_anthropic:
        spoken, session_messages = await _llm_summarize_anthropic(
            llm, system_prompt, session_messages,
            response.tool_calls, exec_result.step_results, tools,
        )
        if sm:
            await sm.save(session_messages)
    else:
        spoken = await _llm_summarize_openai(
            llm, system_prompt, body.transcript,
            response.tool_calls, exec_result.step_results, tools,
        )

    attachments = _extract_attachments(exec_result.step_results)
    updated_name = _extract_updated_name(exec_result.step_results)

    return CommandResponse(
        spoken_response=spoken,
        action_plan=plan,
        device_actions=exec_result.device_actions,
        plan_id=plan.plan_id,
        attachments=attachments,
        updated_user_name=updated_name,
    )


@router.post("/confirm", response_model=CommandResponse)
async def confirm_plan(
    body: ConfirmRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    entry = _pending_plans.pop(body.plan_id, None)
    if entry is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Plan not found or already executed")

    plan, owner_id, session_messages = entry
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
    tools = build_tools()
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

    if synthetic_tool_calls and exec_result.step_results:
        if use_anthropic:
            spoken, session_messages = await _llm_summarize_anthropic(
                llm, system_prompt, session_messages,
                synthetic_tool_calls, exec_result.step_results, tools,
            )
            sm = SessionManager(db, str(user.id))
            await sm.save(session_messages)
        else:
            spoken = await _llm_summarize_openai(
                llm, system_prompt, plan.user_intent,
                synthetic_tool_calls, exec_result.step_results, tools,
            )
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

    attachments = _extract_attachments(exec_result.step_results)
    updated_name = _extract_updated_name(exec_result.step_results)

    return CommandResponse(
        spoken_response=spoken,
        action_plan=plan,
        device_actions=exec_result.device_actions,
        plan_id=plan.plan_id,
        attachments=attachments,
        updated_user_name=updated_name,
    )


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
