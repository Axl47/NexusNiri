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
- [x] (2026-03-13 02:56Z) Rewrite `StageChrome` from the horizontal `ScrollView` prototype into a layout-driven overlay viewport with centered active-slot navigation, header-only strip chrome, and indicator feedback driven by `LayoutPlan.scrollOffset`.
- [x] (2026-03-13 02:56Z) Remove stage-level resize handles and direct strip dragging from the shell UI for this v1 slice, leaving width-policy mutation dormant in the model layer for a later geometry pass.
- [x] (2026-03-13 03:31Z) Implement visible-slot native geometry conformance so every `LayoutPlan.visibleSlotIDs` window stages into its slot rect, the active slot regains focus after the geometry pass, and viewport moves reapply the latest staged layout.
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
- Observation: The stage `GeometryReader` already measures the visible viewport, so `ChromeMetrics.stageGeometry(for:)` has to add the sidebar and topbar dimensions back before constructing `StageGeometry`; otherwise the layout engine sees a double-subtracted viewport and active-slot centering drifts.
  Evidence: local rewrite on 2026-03-13 initially under-sized the layout plan until `Sources/StageChrome/ChromeTheme.swift` began re-inflating the chrome dimensions before calling into `StripLayoutEngine`.
- Observation: The horizontal `ScrollView` stage prototype was creating a second source of strip position truth that obscured whether motion came from workspace state or SwiftUI scrolling.
  Evidence: local rewrite on 2026-03-13 was able to remove `ScrollViewReader`, `proxy.scrollTo`, and shell resize handles while preserving slot/workspace navigation and window choreography by rendering the strip as a clipped overlay driven only by `LayoutPlan.scrollOffset`.
- Observation: The current viewport reporter already emits the stage rect whenever the Nexus window moves, but the choreography dedupe key ignores viewport position so pure window drags do not restage native windows.
  Evidence: local inspection on 2026-03-13 showed `ScreenSpaceFrameReporter` calling `AppEnvironment.updateStageViewportFrame(_:)` while `ChoreographySignature` only compared workspace, scroll state, and slot frames.
- Observation: The first live choreography slice still resolves only the active slot as `.show`, even when the layout engine keeps multiple slots in `visibleSlotIDs`.
  Evidence: local inspection on 2026-03-13 showed `VisibilityCoordinator.transition` parking every non-active slot while `StripLayoutEngine.planLayout` and `WorkspaceSession.updateVisibility(using:)` already track visible and parked slot IDs separately.
- Observation: AX position writes need the slot's top-left screen coordinate, not the bottom-left point that AppKit geometry makes convenient to compute.
  Evidence: local visible-slot geometry tests on 2026-03-13 only matched the stage viewport when `resolvedStageFrame` used `stageViewportFrame.maxY - ChromeMetrics.slotHeaderHeight - slotLayout.frame.y` for Y and delayed focus until after all frame writes.

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
- Decision: Replace the horizontal `ScrollView` stage prototype with a clipped overlay stage driven only by `LayoutPlan.scrollOffset`, and remove stage-level resize affordances from the v1 shell.
  Rationale: the product spec calls for deterministic focus-driven strip navigation and app-owned viewport input; keeping the prototype scroll container and resize handles would keep implying behaviors that this slice explicitly defers.
  Date/Author: 2026-03-13 / Codex
- Decision: Implement native size conformance by staging every visible slot, focusing only once after geometry work, and reapplying the latest layout when the stage viewport frame moves.
  Rationale: the layout engine already defines which slots belong on stage, and delaying focus until the end prevents secondary visible apps from stealing activation while still keeping the current opaque shell and parking heuristics intact.
  Date/Author: 2026-03-13 / Codex

## Outcomes & Retrospective

The repository is no longer empty. It now has a native CLI-first app shape, a working shell UI, clean subsystem boundaries, persistence, diagnostics, and adapter scaffolding. The bootstrap is compiling again under Swift 6.3, `rtk swift test` is passing, and the CLI bundling workflow has been re-verified with the correct `rtk proxy bash` invocation. The shell is also no longer fully mocked: stage layout updates now trigger real AX-backed window staging, parking, and reveal-all replay through the new app-layer choreographer.

The latest shell slice replaces the old horizontally scrollable card prototype with a focus-driven stage model. The active slot is centered by layout state, the strip indicator and header movement are driven directly by `LayoutPlan.scrollOffset`, and the viewport no longer behaves like a user-draggable `ScrollView`. Native size conformance for every visible slot is now implemented: visible windows receive the slot rects computed by the layout engine, the active slot is focused only after the geometry pass completes, and moving the Nexus window replays the latest staged layout. Transparent embedding, deeper runtime rematching, and adapter-specific restore remain follow-up work after this geometry pass.

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

Run `rtk swift test` and expect all package tests to pass. Then run `rtk proxy bash ./scripts/dev-run.sh` and expect a native `Nexus.app` to launch. The sidebar should show numbered workspaces, the topbar should show the active workspace and slot metadata, the strip should center the focused slot, and the diagnostics button should open a panel that shows permission states and environment paths. Slot changes should come from header clicks, topbar arrows, or keyboard shortcuts rather than direct strip dragging. With Accessibility granted, switching slots or workspaces should stage every visible slot into its rect, park only offstage slots, and keep the active slot frontmost after the transition. Moving or resizing the Nexus window should reapply the staged native window frames. Quitting and relaunching the app should still preserve workspace additions, renames, and active-slot selection, though runtime window rematching and adapter-specific restore remain open follow-ups.

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

Plan revision note: this revision records the completed visible-slot native geometry milestone, including the new `WindowControlling` protocol for testable AX mutations, visible-slot staging semantics in the visibility engine, live viewport-follow replay in `AppEnvironment`, and executable-level tests that lock the frame-conversion and final-focus behavior in place.
