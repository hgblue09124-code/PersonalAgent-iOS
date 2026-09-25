# ADR-002: Green Checkpoint Migration

## Status

Accepted.

## Context

Commit `e3e7182523daf711ba23cbc9ec67bd450ef44e5d` is a verified green recovery point. A later broad reorganization produced independent build and architecture-test failures.

## Decision

Start architectural migration from the verified green checkpoint and proceed as independently verifiable slices. Each slice preserves behavior unless explicitly scoped otherwise and must return green before the next slice.

## Why

A green checkpoint gives a known-good rollback and makes failures attributable to a small change set.

## Rule

Never trade a known green baseline for an unbounded migration.
