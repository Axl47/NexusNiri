# Nexus v1 CLI-first bootstrap and shell implementation

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with [`.docs/PLANS.md`](../PLANS.md).

## Purpose / Big Picture

Nexus needs to become a native macOS project shell that can be built and run from the terminal without relying on a hand-managed Xcode project. After this change, a contributor can run terminal scripts, launch a real `Nexus.app`, see the shell chrome described in the UI direction document, create and switch mocked workspaces, inspect permission status, and extend the project through clean subsystem targets instead of starting from an empty repository.

The first observable result is a working CLI workflow:

    cd /Users/axel/Desktop/Code_Projects/Personal/NexusNiri
    rtk proxy bash ./scripts/dev-run.sh

That command should build the Swift package, bundle the executable into `build/Nexus.app`, apply the checked-in `Info.plist`, ad-hoc sign the app, and launch it.

## Progress

- [x] (2026-03-12 23:40Z) Create the root Swift package, subsystem targets, test targets, and CLI bundling scripts.
- [x] (2026-03-12 23:40Z) Add a checked-in macOS app identity with `AppResources/Info.plist` and `AppResources/Nexus.entitlements`.
- [x] (2026-03-12 23:40Z) Add shared domain models, service protocols, JSON persistence, diagnostics, layout, adapter, and stage-chrome foundations.
- [x] (2026-03-12 23:40Z) Implement the first shell UI with workspace CRUD, permission onboarding, mocked strip layout, and diagnostics panel.
- [x] (2026-03-12 23:40Z) Add Tether adapter scaffolding against the sibling repo's existing WebSocket surface plus future `nexus.*` method placeholders.
- [x] (2026-03-13 00:18Z) Repair Swift 6.3 concurrency and compile issues across the bootstrap targets so `rtk swift test` passes again.
- [x] (2026-03-13 00:19Z) Verify the CLI app-bundle workflow with `rtk proxy bash ./scripts/dev-build.sh` and record the `rtk proxy` requirement for nested shell scripts.
- [x] (2026-03-13 00:31Z) Implement the first live window choreography slice so stage layout updates now stage, park, and reveal real app windows through the AX registry.
- [ ] Harden window rematching and runtime binding persistence across live multi-workspace switching against the registry.
- [ ] Implement the first fully working deep Tether restore flow once the sibling app exposes the `nexus.*` contract.

## Surprises & Discoveries

- Observation: A SwiftUI macOS app can be built with `swift build` under Swift 6.3 without a checked-in `.xcodeproj`, but the result is still a raw executable rather than a runnable app bundle.
  Evidence: local feasibility probe on 2026-03-12 produced a successful `swift build` for a minimal SwiftUI app target.
- Observation: Tether does not currently expose REST-style adapter endpoints for Nexus and its usable local control surface is mostly WebSocket-based.
  Evidence: sibling repo inspection of `../Tether/apps/server/src/wsServer.ts` and `../Tether/packages/contracts/src/ws.ts`.
- Observation: Swift 6.3 surfaces strict sendability diagnostics even for bootstrap-only service containers and immutable actor metadata, so small concurrency annotations are required before the package will compile cleanly.
  Evidence: local `rtk swift test` run on 2026-03-13 failed in `AdapterRegistry`, `WorkspaceSession`, `JSONWorkspaceStore`, and `AppEnvironment` until the service contracts and actor metadata were annotated appropriately.
- Observation: The local `rtk` wrapper does not execute nested shell scripts directly; shell-to-shell invocations must go through `rtk proxy bash ...`.
  Evidence: local `rtk proxy bash ./scripts/dev-build.sh` run on 2026-03-13 failed until `scripts/dev-build.sh` and `scripts/dev-run.sh` stopped invoking sibling scripts through plain `rtk`.
- Observation: The stage view's existing layout task is the lowest-risk integration point for live choreography because it already has the concrete `LayoutPlan` needed to turn logical slot changes into native window actions.
  Evidence: local implementation on 2026-03-13 was able to add a single async `onLayoutDidUpdate` callback in `Sources/StageChrome/StageChromeView.swift` and route both sidebar taps and command-menu workspace or slot changes into the same choreography path without rewriting the session model.
- Observation: AX write helpers can live inside the existing registry actor without changing the discovery API surface, which keeps discovery and mutation logic together while preserving the app-layer choreography boundary.
  Evidence: local implementation on 2026-03-13 added frame, minimize, hide, and raise helpers in `Sources/WindowRegistry/AXWindowRegistry.swift` while keeping `WindowRegistryService` unchanged for the current package tests.

## Decision Log

- Decision: Use a root Swift package and CLI app-bundle scripts as the primary development path.
  Rationale: this preserves a native macOS implementation while avoiding an Xcode-driven workflow for daily work.
  Date/Author: 2026-03-12 / Codex
- Decision: Keep persistence JSON-based and human-readable under `~/Library/Application Support/Nexus`.
  Rationale: the project is in bootstrap mode and benefits more from inspectable state than from a heavier persistence layer.
  Date/Author: 2026-03-12 / Codex
- Decision: Implement the first shell with mocked slots while still building the future subsystem boundaries now.
  Rationale: it gives a working UI and storage loop immediately while keeping phase-2 and phase-4 work additive rather than disruptive.
  Date/Author: 2026-03-12 / Codex
- Decision: Treat Tether as the first deep adapter, but scaffold fallback behavior until the sibling repo exposes `nexus.*` methods.
  Rationale: current Tether capabilities cover health and orchestration identity well enough for adapter bootstrap, but not full restore/focus semantics yet.
  Date/Author: 2026-03-12 / Codex
- Decision: Keep bootstrap service types actor-aware instead of suppressing Swift 6.3 diagnostics globally.
  Rationale: targeted fixes (`WorkspaceStore: Sendable`, nonisolated immutable actor URLs, and a sendable adapter registry container) preserve the package's concurrency intent without weakening compiler checks for future live-window work.
  Date/Author: 2026-03-13 / Codex
- Decision: Document and use `rtk proxy bash` for repo shell scripts.
  Rationale: the checked-in helper scripts are ordinary shell files, and the local wrapper only executes raw commands through `proxy`; recording the correct invocation prevents false build failures for future contributors and agents.
  Date/Author: 2026-03-13 / Codex
- Decision: Add an app-layer `WindowChoreographyService` driven by stage-layout updates instead of moving orchestration into the SwiftUI view or the registry actor.
  Rationale: the view already knows the active `LayoutPlan`, while the app layer is the correct place to coordinate registry snapshots, visibility transitions, and diagnostics refreshes. This keeps SwiftUI declarative and leaves the registry responsible for AX read or write primitives rather than workspace policy.
  Date/Author: 2026-03-13 / Codex
- Decision: Use direct AX registry mutations plus app launch or activation fallback for the first live choreography slice, postponing deeper adapter-driven restore semantics.
  Rationale: this proves real staging, parking, and reveal-all behavior for normal apps immediately, while Tether-specific restore remains blocked on the sibling repo's future `nexus.*` contract.
  Date/Author: 2026-03-13 / Codex

## Outcomes & Retrospective

The repository is no longer empty. It now has a native CLI-first app shape, a working shell UI, clean subsystem boundaries, persistence, diagnostics, and adapter scaffolding. The bootstrap is compiling again under Swift 6.3, `rtk swift test` is passing, and the CLI bundling workflow has been re-verified with the correct `rtk proxy bash` invocation. The shell is also no longer fully mocked: stage layout updates now trigger real AX-backed window staging, parking, and reveal-all replay through the new app-layer choreographer. The next implementation milestone is to harden runtime rematching and deep adapter restore, especially for Tether once the sibling repo grows a dedicated Nexus namespace.

## Context and Orientation

The repository started with only design documents in `.docs/`. The architecture brief in `.docs/Nexus_v1_Architecture_Implementation_Plan.md` defines the six core subsystems: Stage Chrome, Window Registry, Workspace Engine, Layout Engine, Visibility Engine, and Adapter Bus. The visual brief in `.docs/ui-direction.md` defines the shell chrome contract: a 52px sidebar, 36px topbar, 28px slot headers, 6px strip indicator, monochrome translucent chrome, instant workspace switches, and centered slot navigation.

This implementation adds a root `Package.swift`, library targets in `Sources/*`, a native app executable target in `Sources/NexusApp`, and CLI bundling scripts in `scripts/`. The app identity files live in `AppResources/` because SwiftPM does not itself produce a runnable `.app` bundle.

## Plan of Work

First, define the package structure, app bundle scripts, and checked-in app identity. Next, codify the architecture document's shared models and service contracts in `Sources/SharedTypes`. Then add core implementations: JSON persistence in `Sources/WorkspaceEngine`, layout planning in `Sources/LayoutEngine`, permission and diagnostics helpers in `Sources/Diagnostics`, window discovery scaffolding in `Sources/WindowRegistry`, visibility planning in `Sources/VisibilityEngine`, adapter registration in `Sources/AdapterBus`, and concrete adapter scaffolds in `Sources/GenericAXAdapter` and `Sources/TetherAdapter`.

After the foundations exist, build the first shell UI in `Sources/StageChrome` and wire the executable app in `Sources/NexusApp`. Seed mocked workspaces from a checked-in JSON resource so the app launches into a usable state on the first run. Finally, add unit tests for shared-model round trips, layout math, persistence, and Tether adapter parsing, then validate the CLI scripts with `rtk ./scripts/dev-build.sh` and `rtk swift test`.

## Concrete Steps

From the repository root, use these commands:

    rtk proxy bash ./scripts/dev-build.sh
    rtk swift test
    rtk proxy bash ./scripts/dev-run.sh

The expected build flow is:

    > rtk proxy bash ./scripts/dev-build.sh
    Building NexusApp with SwiftPM...
    Bundling build/Nexus.app...
    Ad-hoc signing build/Nexus.app...
    Nexus.app ready at .../build/Nexus.app

## Validation and Acceptance

Run `rtk swift test` and expect all package tests to pass. Then run `rtk proxy bash ./scripts/dev-run.sh` and expect a native `Nexus.app` to launch. The sidebar should show numbered workspaces, the topbar should show the active workspace and slot metadata, the strip should center the focused slot, and the diagnostics button should open a panel that shows permission states and environment paths. With Accessibility granted, switching slots or workspaces should now attempt to move visible windows into the active stage, park offstage windows, and replay reveal-all against the most recent staged set. Quitting and relaunching the app should still preserve workspace additions, renames, and active-slot selection, though runtime window rematching remains an open follow-up.

## Idempotence and Recovery

The scripts are designed to be repeatable. Re-running `rtk proxy bash ./scripts/dev-build.sh` replaces `build/Nexus.app` safely. Re-running `rtk proxy bash ./scripts/dev-run.sh` rebuilds and reopens the app bundle. `rtk proxy bash ./scripts/dev-clean.sh` removes only generated build outputs and leaves checked-in sources untouched.

## Artifacts and Notes

Important files added by this plan:

    Package.swift
    AppResources/Info.plist
    AppResources/Nexus.entitlements
    scripts/dev-build.sh
    scripts/dev-run.sh
    scripts/make-app-bundle.sh
    Sources/NexusApp/
    Sources/SharedTypes/
    Sources/WorkspaceEngine/
    Sources/WindowRegistry/
    Sources/LayoutEngine/
    Sources/VisibilityEngine/
    Sources/AdapterBus/
    Sources/Diagnostics/
    Sources/GenericAXAdapter/
    Sources/TetherAdapter/
    Sources/StageChrome/

## Interfaces and Dependencies

The package exposes one executable target, `NexusApp`, and the following internal library boundaries:

    SharedTypes
      Workspace, Slot, AppBinding, RuntimeBinding, LayoutState, VisibilityState,
      AdapterState, SessionSnapshot, StageGeometry, WindowCandidate, LayoutPlan,
      VisibilityAction, DiagnosticsSnapshot, PermissionStatus, HotkeyCommand,
      WorkspaceStore, WindowRegistryService, LayoutComputing,
      VisibilityCoordinating, FocusCoordinating, NexusAdapter

    WorkspaceEngine
      JSONWorkspaceStore
      WorkspaceSession

    LayoutEngine
      StripLayoutEngine

    WindowRegistry
      AXWindowRegistry

    VisibilityEngine
      VisibilityCoordinator

    AdapterBus
      AdapterRegistry

    GenericAXAdapter
      GenericAXAdapter

    TetherAdapter
      TetherAdapter

    Diagnostics
      DiagnosticsCenter

    StageChrome
      StageChromeView
      DiagnosticsPanelController

Plan revision note: this revision records the verified `rtk proxy bash` shell workflow, the targeted Swift 6.3 concurrency fixes, and the first live AX-backed choreography slice that connects stage layout updates to real window staging and reveal-all behavior.
