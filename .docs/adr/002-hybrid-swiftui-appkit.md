# ADR 002: Hybrid SwiftUI and AppKit shell composition

## Status

Accepted on 2026-03-12.

## Context

The shell must render modern chrome quickly, but Nexus also needs AppKit and Accessibility APIs for panels, focus management, and future window choreography.

## Decision

Nexus uses SwiftUI for the main shell surfaces and AppKit for application lifecycle hooks, visual-effect views, window configuration, diagnostics panels, and future Accessibility-backed services.

## Consequences

- The shell UI stays concise and testable.
- AppKit remains available where SwiftUI is not enough.
- The codebase can grow toward phase-2 and phase-4 functionality without a later UI rewrite.
