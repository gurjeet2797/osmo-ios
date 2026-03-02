from __future__ import annotations

import importlib
import tomllib
from pathlib import Path

import structlog

from app.tools.registry import register_skill
from app.tools.skill import SkillManifest

log = structlog.get_logger()

_loaded = False

SKILLS_DIR = Path(__file__).parent / "skills"


def discover_and_load_skills() -> list[SkillManifest]:
    """Scan skills/ subdirectories, load skill.toml manifests, and import tool modules.

    Idempotent — safe to call multiple times; only loads on the first call.
    Returns the list of loaded SkillManifest objects.
    """
    global _loaded
    if _loaded:
        from app.tools.registry import get_skill_manifests
        return get_skill_manifests()

    manifests: list[SkillManifest] = []

    if not SKILLS_DIR.is_dir():
        log.warning("skills directory not found", path=str(SKILLS_DIR))
        _loaded = True
        return manifests

    for skill_dir in sorted(SKILLS_DIR.iterdir()):
        if not skill_dir.is_dir():
            continue

        toml_path = skill_dir / "skill.toml"
        if not toml_path.exists():
            continue

        with open(toml_path, "rb") as f:
            data = tomllib.load(f)

        skill_data = data.get("skill", {})
        manifest = SkillManifest(
            name=skill_data["name"],
            display_name=skill_data["display_name"],
            description=skill_data["description"],
            tool_modules=skill_data.get("tool_modules", []),
            planner_instructions=skill_data.get("planner_instructions", []),
        )

        # Import each tool module — their module-level register_tool() calls do the work
        for module_name in manifest.tool_modules:
            fqn = f"app.tools.skills.{skill_dir.name}.{module_name}"
            try:
                importlib.import_module(fqn)
                log.debug("loaded tool module", module=fqn)
            except Exception:
                log.exception("failed to load tool module", module=fqn)

        register_skill(manifest)
        manifests.append(manifest)
        log.debug("loaded skill", skill=manifest.name, tools=manifest.tool_modules)

    _loaded = True
    log.info("skill discovery complete", count=len(manifests))
    return manifests
