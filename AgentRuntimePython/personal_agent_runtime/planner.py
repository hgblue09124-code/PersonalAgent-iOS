"""Small deterministic request planner. No I/O and no execution authority."""
from __future__ import annotations

import re
import unicodedata
from collections.abc import Iterable

from .contracts import AgentIntent, AgentPlan, IntentKind, PlanKind

_CREATE_FILE = re.compile(
    r"\b(?:tao|tạo|create|make|write)\s+(?:giup\s+)?(?:mot\s+)?(?:file|tep|tệp)\b",
    re.IGNORECASE,
)
_PATH = re.compile(r"(?:workspace/)[A-Za-z0-9._/-]+")
_CONTENT = re.compile(r"(?:noi\s*dung|nội\s*dung|content)\s*:\s*(.+)$", re.IGNORECASE | re.DOTALL)
_CREATE_SKILL = "workspace.create-file"


def _normalize(text: str) -> str:
    collapsed = " ".join(text.strip().split())
    return unicodedata.normalize("NFC", collapsed)


def _has_create_file_intent(text: str) -> bool:
    folded = text.casefold()
    if _CREATE_FILE.search(folded):
        return True
    return bool(re.search(r"\btao\s+(?:mot\s+)?file\b", folded))


def _extract_proposal(text: str) -> tuple[str | None, str | None]:
    path_match = _PATH.search(text)
    content_match = _CONTENT.search(text)
    path = path_match.group(0) if path_match else None
    content = content_match.group(1).strip() if content_match else None
    return path, content


def plan_request(text: str, allowed_skill_ids: Iterable[str] = ()) -> AgentPlan:
    """Return a proposal or clarification; never execute the requested action.

    allowed_skill_ids is a caller-provided scope hint, not an authorization grant.
    Swift must independently enforce policy and capability checks.
    """
    normalized = _normalize(text)
    if not normalized:
        intent = AgentIntent(IntentKind.UNKNOWN, normalized)
        return AgentPlan(
            PlanKind.CLARIFY,
            intent,
            "Please describe what you want the Agent to do.",
            ("request",),
        )

    if _has_create_file_intent(normalized):
        intent = AgentIntent(IntentKind.CREATE_FILE, normalized)
        path, content = _extract_proposal(normalized)
        missing = tuple(
            field for field, value in (("path", path), ("content", content)) if not value
        )
        if missing:
            labels = {"path": "file path", "content": "file content"}
            requested = " and ".join(labels[item] for item in missing)
            return AgentPlan(
                PlanKind.CLARIFY,
                intent,
                f"Please provide the {requested}.",
                missing,
            )

        if _CREATE_SKILL not in set(allowed_skill_ids):
            return AgentPlan(
                PlanKind.UNSUPPORTED,
                intent,
                "The file-writing capability is not available in the current Agent scope.",
            )

        return AgentPlan(
            PlanKind.PROPOSE_SKILL,
            intent,
            "Proposed a file-write action for Swift policy validation.",
            skill_id=_CREATE_SKILL,
            arguments={"path": path, "content": content},
        )

    return AgentPlan(
        PlanKind.RESPOND,
        AgentIntent(IntentKind.CHAT, normalized),
        "Handle this as a conversational request; no tool action was proposed.",
    )
