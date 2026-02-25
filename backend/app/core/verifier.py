from __future__ import annotations

import structlog

from app.schemas.command import VerificationResult
from app.schemas.device import DeviceActionResult
from app.tools.base import ToolContext
from app.tools.registry import get_tool

log = structlog.get_logger()


async def verify_server_step(
    tool_name: str,
    args: dict,
    result: dict,
    context: ToolContext,
) -> VerificationResult:
    """Re-read and compare after a server-side write."""
    tool = get_tool(tool_name)
    if tool is None:
        return VerificationResult(matched=False, discrepancies=[f"Unknown tool: {tool_name}"])

    verification = await tool.verify(args, result, context)
    log.info(
        "verifier.server",
        tool=tool_name,
        matched=verification.matched,
        discrepancies=verification.discrepancies,
    )
    return verification


def verify_device_result(
    device_result: DeviceActionResult,
) -> VerificationResult:
    """Verify a device-side action result reported by the iOS app."""
    if not device_result.success:
        return VerificationResult(
            matched=False,
            discrepancies=[f"Device execution failed: {device_result.error or 'unknown error'}"],
        )

    log.info(
        "verifier.device",
        action_id=device_result.action_id,
        matched=True,
    )
    return VerificationResult(matched=True)
