# Dynamic Slot Width Reconciliation for Minimum-Width Windows and Focused External Resizes

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with `.docs/PLANS.md`.

## Purpose / Big Picture

Nexus currently treats slot widths as write-only layout input. After this change, the shell will learn when a visible app refuses to shrink to the requested width, and it will also learn the width a user leaves a focused native window at after resizing it externally. The learned width is persisted back into the slot `widthPolicy`, so the shell strip, slot headers, and real windows converge on the same width instead of drifting.

## Progress

- [x] (2026-03-13 22:41Z) Captured the approved design as an implementation ExecPlan and created a live working list.
- [x] (2026-03-13 20:22Z) Refactored `Sources/WorkspaceEngine/WorkspaceSession.swift` so manual resize and observed-width refresh share one clamp-and-persist helper.
- [x] (2026-03-13 20:22Z) Added visible-slot width reconciliation and focused-window width debounce in `Sources/NexusApp/AppEnvironment.swift`.
- [x] (2026-03-13 20:23Z) Extended tests in `Tests/WorkspaceEngineTests/WorkspaceEngineTests.swift` and `Tests/NexusAppTests/WindowChoreographyServiceTests.swift`.
- [x] (2026-03-13 20:23Z) Updated `AGENTS.md`, completed targeted verification, and recorded final outcomes.

## Surprises & Discoveries

- Observation: the existing `AppEnvironment` test harness does not automatically trigger a second choreography apply after session state changes because the real SwiftUI `StageChromeView` is absent in tests.
  Evidence: the width-correction tests needed to assert the persisted slot width directly and, for focus-policy replay, manually invoke a second `applyChoreography(...)` with the updated workspace and layout.

- Observation: the existing focused-window monitor path was already safe to extend because width sync can run on every poll without touching the selection fingerprint.
  Evidence: keeping `FocusedWindowFingerprint` width-free while adding a separate debounced geometry path allowed the new focused-resize test to pass without regressing reverse-focus tests.

## Decision Log

- Decision: Keep persisted widths in the existing fraction-based `SizePolicy` model instead of introducing a new remembered-pixel field.
  Rationale: the current layout engine already derives slot width from `SizePolicy`, so using the same model keeps persistence and layout behavior aligned.
  Date/Author: 2026-03-13 / Codex

- Decision: Do not add a new adapter feedback protocol in this slice.
  Rationale: width learning will be observation-driven through the existing window registry, which keeps the first implementation smaller and lets adapter-managed slots participate only when they expose a matchable native window.
  Date/Author: 2026-03-13 / Codex

- Decision: Persist geometry feedback by setting `SelectionOrigin.nativeGeometrySync` on actual slot-width changes and mapping it to `.preserveExternalFocus`.
  Rationale: geometry corrections should restage with the user’s external window focus preserved, but they must not masquerade as reverse-focus selection changes.
  Date/Author: 2026-03-13 / Codex

## Outcomes & Retrospective

The feature is implemented. Nexus now learns width from two observation paths: visible-slot post-stage snapshots for minimum-width correction and a debounced focused-window poller for user-driven external resizes. Both paths persist through the existing fraction-based `widthPolicy` model, and the resulting replay uses focus-preserving choreography instead of active-slot refocus.

The main remaining limitation is deliberate: there is still no adapter-specific geometry feedback protocol. Adapter-managed slots only participate when a native window can be observed and matched through the existing window registry.

## Context and Orientation

`Sources/WorkspaceEngine/WorkspaceSession.swift` owns persisted workspace and slot state, including the current `resizeSlot` API that turns a requested pixel width into a fraction stored on the slot `widthPolicy`. `Sources/LayoutEngine/StripLayoutEngine.swift` reads those width policies and produces a `LayoutPlan`, whose `slotLayouts` feed both the shell UI and native window choreography.

`Sources/NexusApp/AppEnvironment.swift` is the app-layer ordering gate for choreography. It receives layout updates from `Sources/StageChrome/StageChromeView.swift`, serializes choreography requests, refreshes runtime bindings after each apply, and runs the focused-window polling loop used for reverse focus sync. `Sources/NexusApp/WindowChoreographyService.swift` performs the actual staging actions but does not own persisted slot geometry, so width learning belongs in `AppEnvironment` and `WorkspaceSession`, not in the choreography service.

The tests that lock these behaviors live in `Tests/WorkspaceEngineTests/WorkspaceEngineTests.swift` and `Tests/NexusAppTests/WindowChoreographyServiceTests.swift`. The latter file already contains recording doubles for the window registry and choreography service, which will be extended so width feedback can be exercised across repeated applies and focused-window polls.

## Plan of Work

First, refactor `WorkspaceSession` so both manual shell resize and observed native width feedback call one helper that clamps against slot minimum and maximum values, writes the resulting fraction, and returns whether anything materially changed. Add a new `SelectionOrigin.nativeGeometrySync` case so geometry-driven width learning can request focus-preserving choreography without pretending a focus change occurred.

Next, modify `AppEnvironment` so the post-choreography refresh step snapshots windows once, updates runtime bindings as before, and also reconciles the observed width of visible matched windows against the planned slot widths. When an app clamps itself wider than requested, the slot width is updated and the normal SwiftUI layout pipeline produces one corrective restage.

Then extend the focused-window monitor so every poll still runs selection sync through `handleFocusedWindowCandidate(_:)`, but width sync is handled separately. The new path should only track the focused visible window in the selected workspace, debounce width changes until they stabilize, and then persist the learned width through `WorkspaceSession.refreshSlotWidth(...)`.

Finally, update the tests to prove the new width refresh semantics, visible-slot post-stage correction, focused-window debounce behavior, and convergence to at most one corrective replay. After the runtime changes are stable, update `AGENTS.md` with the new file-level guidance and run the targeted test commands.

## Concrete Steps

From the repository root `/Users/axel/Desktop/Code_Projects/Personal/NexusNiri`, run:

    rtk swift test --filter WorkspaceEngineTests
    rtk swift test --filter WindowChoreographyServiceTests

If either command fails because the test runner does not support the filter syntax in this toolchain, rerun the full suite with:

    rtk swift test

## Validation and Acceptance

Acceptance requires both automated and manual proof. The automated proof is that the updated workspace and app-environment tests pass and demonstrate: width refresh is clamped and persisted correctly, visible windows wider than their planned slot trigger a single corrective width update, focused-window resize feedback waits for stable width before persisting, and repeated identical observations do not cause infinite replays.

Manual acceptance requires running the app and observing three scenarios: a minimum-width app widens itself after staging and Nexus corrects to that width, a focused native window resized by the user keeps its new width when revisited, and a non-focused visible neighbor does not change slot width state when resized. Tether should only participate if it is discoverable through the existing window registry.

## Idempotence and Recovery

The code changes are additive and safe to re-run. If the width feedback loop misbehaves during development, disable the new `AppEnvironment` reconciliation helpers first while keeping the `WorkspaceSession` API and tests as the stable checkpoint. The new persisted data still uses existing `SizePolicy` fields, so there is no schema migration or one-way data conversion to undo.

## Artifacts and Notes

Verification commands run from `/Users/axel/Desktop/Code_Projects/Personal/NexusNiri`:

    rtk swift test --filter WorkspaceEngineTests
    rtk swift test --filter WindowChoreographyServiceTests
    rtk swift test

Observed result:

    ✔ Test run with 67 tests in 0 suites passed after 0.487 seconds.

## Interfaces and Dependencies

In `Sources/WorkspaceEngine/WorkspaceSession.swift`, define:

    @discardableResult
    public func refreshSlotWidth(
        workspaceID: String,
        slotID: String,
        observedWidth: Double,
        viewportWidth: Double,
        persist: Bool = true
    ) -> Bool

This method must share the same clamp-and-fraction logic as `resizeSlot(...)`, return `true` only when the stored width policy materially changes, and set `lastSelectionOrigin = .nativeGeometrySync` only on actual change.

In `Sources/NexusApp/AppEnvironment.swift`, add internal helpers that:

    1. snapshot windows once after each choreography apply,
    2. refresh runtime bindings from that snapshot,
    3. reconcile visible matched slot widths from that snapshot, and
    4. debounce focused-window width updates separately from focus-selection dedupe.

No new `WindowRegistryService` or adapter protocol requirements should be introduced in this milestone.

Plan note: updated on 2026-03-13 after implementation to record the shipped behavior, verification evidence, and the decision to keep adapter feedback observation-only in this slice.
