# capabilities-migration-gate
ID
capabilities-migration-gate

PURPOSE
Move Modules, Skills, and Tools into canonical Capabilities ownership without behavior rewrite.

WHEN
Executing the Capabilities physical migration group.

RULE
Move source paths, update Package.swift and path-sensitive CI/tests, then require the full verification gate before accepting the migration.

VERIFY
PR #94 reports 340 tests across 46 suites and Apple/IPA verification in its documented migration evidence.

STATUS
CONFIRMED

SOURCE
PR #94 — Capabilities group canonical migration