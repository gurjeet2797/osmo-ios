from __future__ import annotations

import uuid
from typing import Any

import structlog

from app.schemas.action_plan import ActionPlan, ActionStep
from app.schemas.device import DeviceAction
from app.tools.base import ToolContext
from app.tools.registry import get_tool

log = structlog.get_logger()


class StepResult:
    def __init__(
        self,
        step: ActionStep,
        success: bool,
        result: dict[str, Any] | None = None,
        error: str | None = None,
        device_action: DeviceAction | None = None,
    ):
        self.step = step
        self.success = success
        self.result = result
        self.error = error
        self.device_action = device_action


class ExecutionResult:
    def __init__(self):
        self.step_results: list[StepResult] = []
        self.device_actions: list[DeviceAction] = []
        self.all_succeeded: bool = True

    def add(self, sr: StepResult) -> None:
        self.step_results.append(sr)
        if sr.device_action:
            self.device_actions.append(sr.device_action)
        if not sr.success:
            self.all_succeeded = False


class Executor:
    def __init__(self, executed_keys: set[str] | None = None):
        self._executed_keys: set[str] = executed_keys or set()

    async def execute_plan(
        self,
        plan: ActionPlan,
        context: ToolContext,
    ) -> ExecutionResult:
        result = ExecutionResult()

        for step in plan.steps:
            if step.requires_confirmation:
                continue

            sr = await self._execute_step(step, context)
            result.add(sr)

            if not sr.success:
                log.error(
                    "executor.step_failed",
                    tool=step.tool_name,
                    error=sr.error,
                    plan_id=plan.plan_id,
                )
                break

        return result

    async def execute_confirmed_plan(
        self,
        plan: ActionPlan,
        context: ToolContext,
    ) -> ExecutionResult:
        """Execute all steps in a confirmed plan, including those that needed confirmation."""
        result = ExecutionResult()

        for step in plan.steps:
            sr = await self._execute_step(step, context)
            result.add(sr)

            if not sr.success:
                log.error(
                    "executor.step_failed",
                    tool=step.tool_name,
                    error=sr.error,
                    plan_id=plan.plan_id,
                )
                break

        return result

    async def _execute_step(self, step: ActionStep, context: ToolContext) -> StepResult:
        if step.idempotency_key in self._executed_keys:
            log.info("executor.idempotent_skip", key=step.idempotency_key, tool=step.tool_name)
            return StepResult(step=step, success=True, result={"skipped": True})

        if step.execution_target == "device":
            return self._build_device_action(step)

        tool = get_tool(step.tool_name)
        if tool is None:
            return StepResult(step=step, success=False, error=f"Unknown tool: {step.tool_name}")

        try:
            result = await tool.execute(step.args, context)
            self._executed_keys.add(step.idempotency_key)
            log.info("executor.step_ok", tool=step.tool_name, key=step.idempotency_key)
            return StepResult(step=step, success=True, result=result)
        except Exception as exc:
            log.exception("executor.step_exception", tool=step.tool_name)
            return StepResult(step=step, success=False, error=str(exc))

    def _build_device_action(self, step: ActionStep) -> StepResult:
        action = DeviceAction(
            action_id=uuid.uuid4().hex,
            tool_name=step.tool_name,
            args=step.args,
            idempotency_key=step.idempotency_key,
        )
        self._executed_keys.add(step.idempotency_key)
        return StepResult(step=step, success=True, device_action=action)
