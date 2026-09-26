# canonical-layer-structure
ID
canonical-layer-structure

PURPOSE
Give the repository one explicit physical architecture axis.

WHEN
The repository contains overlapping legacy source locations.

RULE
Use Kernel, Runtime, Capabilities, Providers, Memory, Storage, Composition, App, and Tests as canonical domains; treat structural migration separately from behavior redesign.

VERIFY
PR #86 moved 79 source files and preserved module/product boundaries without intentional runtime behavior change.

STATUS
CONFIRMED

SOURCE
PR #86 — canonical layer consolidation