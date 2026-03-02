from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class SkillManifest:
    name: str                                   # "calendar"
    display_name: str                           # "Calendar"
    description: str                            # one-liner for system prompt
    tool_modules: list[str] = field(default_factory=list)   # ["google_calendar", "ios_eventkit"]
    planner_instructions: list[str] = field(default_factory=list)  # skill-specific LLM rules
