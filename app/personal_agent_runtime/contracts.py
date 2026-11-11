"""Typed contracts shared by Python planning and future bridges.

These values describe proposals only. They do not represent authorization or execution.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any

PLAN_SCHEMA_VERSION = 1


class IntentKind(str, Enum):
    CHAT = "chat"
    CREATE_FILE = "create_file"
    UNKNOWN = "unknown"


class PlanKind(str, Enum):
    RESPOND = "respond"
    CLARIFY = "clarify"
    PROPOSE_SKILL = "propose_skill"
    UNSUPPORTED = "unsupported"


@dataclass(frozen=True)
class AgentIntent:
    kind: IntentKind
    normalized_text: str


@dataclass(frozen=True)
class AgentPlan:
    kind: PlanKind
    intent: AgentIntent
    message: str
    missing_fields: tuple[str, ...] = ()
    skill_id: str | None = None
    arguments: dict[str, Any] = field(default_factory=dict)

    @property
    def is_executable(self) -> bool:
        """Python plans are never executable; Swift must validate and execute proposals."""
        return False

    def to_dict(self) -> dict[str, Any]:
        """Serialize a versioned envelope suitable for a future Swift/Python bridge."""
        return {
            "schema_version": PLAN_SCHEMA_VERSION,
            "kind": self.kind.value,
            "intent": {
                "kind": self.intent.kind.value,
                "normalized_text": self.intent.normalized_text,
            },
            "message": self.message,
            "missing_fields": list(self.missing_fields),
            "skill_id": self.skill_id,
            "arguments": dict(self.arguments),
            "is_executable": False,
        }
