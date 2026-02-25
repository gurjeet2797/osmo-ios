from __future__ import annotations

from typing import Annotated, Any

import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

import app.tools.google_calendar  # noqa: F401 — register tools
import app.tools.ios_eventkit  # noqa: F401 — register tools
from app.connectors.google_calendar import credentials_from_encrypted
from app.connectors.llm import LLMClient
from app.core.executor import Executor
from app.core.planner import Planner
from app.core.policy import evaluate
from app.core.verifier import verify_device_result, verify_server_step
from app.db.session import get_db
from app.dependencies import get_current_user
from app.models.audit import AuditLog
from app.models.user import User
from app.schemas.action_plan import ActionPlan
from app.schemas.command import (
    CommandRequest,
    CommandResponse,
    ConfirmRequest,
    DeviceResultRequest,
)
from app.tools.base import ToolContext

log = structlog.get_logger()

router = APIRouter()

_pending_plans: dict[str, tuple[ActionPlan, str]] = {}


def _build_context(user: User) -> ToolContext:
    google_creds = None
    if user.google_tokens_encrypted:
        google_creds = credentials_from_encrypted(user.google_tokens_encrypted)
    return ToolContext(
        user_id=str(user.id),
        google_credentials=google_creds,
        timezone=user.timezone,
    )


def _spoken_summary(plan: ActionPlan, exec_result: Any) -> str:
    """Generate a simple spoken response summarizing what was done."""
    if not plan.steps:
        return "I didn't find any actions to take."

    parts = []
    for sr in exec_result.step_results:
        if sr.device_action:
            parts.append(f"Sending '{sr.step.tool_name}' to your device.")
        elif sr.success:
            parts.append(f"Done: {sr.step.tool_name}.")
        else:
            parts.append(f"Failed: {sr.step.tool_name} — {sr.error}")

    return " ".join(parts) if parts else f"Planned: {plan.user_intent}"


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
    llm = LLMClient()
    planner = Planner(llm)

    plan_or_clarify = await planner.plan(
        transcript=body.transcript,
        timezone=body.timezone,
        locale=body.locale,
        linked_providers=body.linked_providers,
    )

    if isinstance(plan_or_clarify, dict) and plan_or_clarify.get("clarification_needed"):
        return CommandResponse(
            spoken_response=plan_or_clarify["clarification_needed"],
            requires_confirmation=False,
        )

    plan: ActionPlan = plan_or_clarify  # type: ignore[assignment]

    policy_result = evaluate(plan)
    if policy_result.blocked:
        return CommandResponse(
            spoken_response=policy_result.block_reason or "This action is blocked by policy.",
            action_plan=plan,
        )

    if plan.needs_confirmation:
        _pending_plans[plan.plan_id] = (plan, str(user.id))

        phrases = [
            s.confirmation_phrase
            for s in plan.steps
            if s.requires_confirmation and s.confirmation_phrase
        ]
        prompt = " ".join(phrases) if phrases else f"Confirm: {plan.user_intent}?"

        return CommandResponse(
            spoken_response=prompt,
            action_plan=plan,
            requires_confirmation=True,
            confirmation_prompt=prompt,
            plan_id=plan.plan_id,
        )

    context = _build_context(user)
    executor = Executor()
    exec_result = await executor.execute_plan(plan, context)

    for sr in exec_result.step_results:
        if sr.success and sr.result and sr.step.execution_target == "server":
            await verify_server_step(sr.step.tool_name, sr.step.args, sr.result, context)

        await _audit(
            db,
            str(user.id),
            plan.plan_id,
            sr.step.tool_name,
            sr.step.args,
            sr.result,
            "ok" if sr.success else "error",
            sr.error,
        )

    return CommandResponse(
        spoken_response=_spoken_summary(plan, exec_result),
        action_plan=plan,
        device_actions=exec_result.device_actions,
        plan_id=plan.plan_id,
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

    plan, owner_id = entry
    if owner_id != str(user.id):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Plan belongs to another user")

    context = _build_context(user)
    executor = Executor()
    exec_result = await executor.execute_confirmed_plan(plan, context)

    for sr in exec_result.step_results:
        if sr.success and sr.result and sr.step.execution_target == "server":
            await verify_server_step(sr.step.tool_name, sr.step.args, sr.result, context)

        await _audit(
            db,
            str(user.id),
            plan.plan_id,
            sr.step.tool_name,
            sr.step.args,
            sr.result,
            "ok" if sr.success else "error",
            sr.error,
        )

    return CommandResponse(
        spoken_response=_spoken_summary(plan, exec_result),
        action_plan=plan,
        device_actions=exec_result.device_actions,
        plan_id=plan.plan_id,
    )


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
