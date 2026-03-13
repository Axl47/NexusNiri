# ADR 003: Human-readable JSON persistence

## Status

Accepted on 2026-03-12.

## Context

The repository is in bootstrap mode and needs inspectable, low-friction persistence for workspaces, runtime state, adapter snapshots, and logs.

## Decision

Nexus persists state as JSON files under `~/Library/Application Support/Nexus/`. Durable configuration, runtime state, adapter snapshots, and logs are separated by directory rather than combined into a database.

## Consequences

- State is easy to inspect, diff, back up, and reset manually.
- The store is simple to evolve while the data model settles.
- A future migration to another storage layer remains possible because the subsystem boundary is the `WorkspaceStore` protocol.
