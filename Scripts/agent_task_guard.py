#!/usr/bin/env python3
"""Validate Agent task contracts and prevent changes outside their declared scope."""
from __future__ import annotations
import argparse
import fnmatch
import json
import subprocess
import sys
from pathlib import Path

REQUIRED = {"id", "title", "status", "goal", "context", "allowed_paths", "forbidden_changes", "acceptance_criteria", "verification", "dependencies", "recovery"}
STATUSES = {"ready", "blocked", "in_progress", "verified"}

def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)

def load_task(path: str) -> dict:
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read task JSON {path}: {exc}")
    if not isinstance(data, dict):
        fail("task root must be a JSON object")
    missing = sorted(REQUIRED - data.keys())
    unknown = sorted(data.keys() - REQUIRED - {"evidence"})
    if missing:
        fail("missing required fields: " + ", ".join(missing))
    if unknown:
        fail("unknown fields: " + ", ".join(unknown))
    if not isinstance(data["id"], str) or not data["id"].strip():
        fail("id must be a non-empty string")
    if data["status"] not in STATUSES:
        fail("status must be one of: " + ", ".join(sorted(STATUSES)))
    for key in ("title", "goal", "context", "recovery"):
        if not isinstance(data[key], str) or not data[key].strip():
            fail(f"{key} must be a non-empty string")
    for key in ("allowed_paths", "forbidden_changes", "acceptance_criteria", "verification", "dependencies"):
        if not isinstance(data[key], list):
            fail(f"{key} must be an array")
    for key in ("allowed_paths", "forbidden_changes", "acceptance_criteria", "verification"):
        if not data[key] or any(not isinstance(item, str) or not item.strip() for item in data[key]):
            fail(f"{key} must contain non-empty strings")
    for pattern in data["allowed_paths"]:
        normalized = pattern.replace("\\", "/")
        if normalized.startswith("/") or ".." in normalized.split("/") or any(c in normalized for c in ("\n", "\r")):
            fail(f"unsafe allowed_paths entry: {pattern!r}")
    if data["status"] == "verified" and not data.get("evidence"):
        fail("status=verified requires non-empty evidence; do not self-certify without results")
    if "evidence" in data and (not isinstance(data["evidence"], list) or any(not isinstance(x, str) or not x.strip() for x in data["evidence"])):
        fail("evidence must be an array of non-empty strings")
    print(f"PASS: task contract {data['id']} is structurally valid")
    return data

def changed_files(base: str) -> list[str]:
    try:
        result = subprocess.run(["git", "diff", "--name-only", "--diff-filter=ACDMRTUXB", f"{base}...HEAD"], check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as exc:
        fail(f"git diff failed; ensure base ref {base!r} exists and is fetched: {exc.stderr.strip()}")
    return [line.strip().replace("\\", "/") for line in result.stdout.splitlines() if line.strip()]

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    validate = sub.add_parser("validate", help="validate task contract fields")
    validate.add_argument("task")
    scope = sub.add_parser("check-diff", help="fail if changed files exceed task scope")
    scope.add_argument("task")
    scope.add_argument("--base", default="origin/main")
    args = parser.parse_args()
    task = load_task(args.task)
    if args.command == "check-diff":
        files = changed_files(args.base)
        if not files:
            print("WARN: no changed files found between base and HEAD")
        out_of_scope = [path for path in files if not any(fnmatch.fnmatchcase(path, pattern) for pattern in task["allowed_paths"])]
        if out_of_scope:
            fail("changed files outside allowed_paths:\n  " + "\n  ".join(out_of_scope))
        print(f"PASS: {len(files)} changed file(s) are within task scope")
if __name__ == "__main__":
    main()
