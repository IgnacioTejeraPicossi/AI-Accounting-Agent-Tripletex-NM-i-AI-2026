"""Discovers SKILL.md files from subdirectories and builds a registry."""
from pathlib import Path
import re


class SkillRegistry:
    def __init__(self, skills_dir: Path):
        self._skills: dict[str, dict] = {}
        self._load(skills_dir)

    def _load(self, skills_dir: Path) -> None:
        if not skills_dir.exists():
            return
        for skill_dir in sorted(skills_dir.iterdir()):
            if not skill_dir.is_dir():
                continue
            skill_file = skill_dir / "SKILL.md"
            if not skill_file.exists():
                continue
            body = skill_file.read_text(encoding="utf-8")
            description = self._extract_description(body)
            self._skills[skill_dir.name] = {
                "description": description,
                "body": body,
            }

    @staticmethod
    def _extract_description(body: str) -> str:
        """Extract the **Description:** line from skill body for the system prompt."""
        for line in body.splitlines():
            if line.startswith("**Description:**"):
                return line.replace("**Description:**", "").strip()
            if line.startswith("# "):
                title = line.lstrip("# ").strip()
                # Fall through to find description line
        # Fallback: second non-empty line after the heading
        lines = [l.strip() for l in body.splitlines() if l.strip()]
        return lines[1] if len(lines) > 1 else "No description"

    def list_skills(self) -> list[tuple[str, dict]]:
        return [(name, {"description": meta["description"]}) for name, meta in self._skills.items()]

    def get_skill_body(self, name: str) -> str | None:
        skill = self._skills.get(name)
        return skill["body"] if skill else None
