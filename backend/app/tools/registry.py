from __future__ import annotations

from app.tools.base import BaseTool
from app.tools.skill import SkillManifest

_REGISTRY: dict[str, BaseTool] = {}
_SKILLS: list[SkillManifest] = []


def register_tool(tool: BaseTool) -> None:
    _REGISTRY[tool.name] = tool


def register_skill(manifest: SkillManifest) -> None:
    _SKILLS.append(manifest)


def get_skill_manifests() -> list[SkillManifest]:
    return list(_SKILLS)


def get_tool(name: str) -> BaseTool | None:
    return _REGISTRY.get(name)


def all_tools() -> list[BaseTool]:
    return list(_REGISTRY.values())


def server_tools() -> list[BaseTool]:
    return [t for t in _REGISTRY.values() if t.execution_target == "server"]


def device_tools() -> list[BaseTool]:
    return [t for t in _REGISTRY.values() if t.execution_target == "device"]


def llm_tool_specs() -> list[dict]:
    return [t.to_llm_spec() for t in _REGISTRY.values()]
