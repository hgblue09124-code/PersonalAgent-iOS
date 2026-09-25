# ADR-001: Explicit Layered Architecture

## Status

Accepted.

## Context

Working capabilities span kernel, runtime, providers, memory, storage, capabilities and UI. Large simultaneous reorganizations create failures that are difficult to localize.

## Decision

Use explicit responsibility boundaries with Composition as the wiring root, Runtime as execution orchestration, Kernel as stable contracts/ports/invariants, and infrastructure domains behind contracts.

SwiftPM target boundaries remain first-class. Folder aesthetics do not override the dependency graph.

## Why

This reduces responsibility concentration, limits vendor leakage and makes migration independently testable.

## Consequences

Some existing code will require gradual extraction. Boundary tests become architectural enforcement. Target architecture must not be mistaken for current implementation.

## Rejected

A single migration that simultaneously moves folders, changes dependencies and changes runtime behavior.
