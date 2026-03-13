# Niri edge-sliver stage for real macOS windows

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with [`.docs/PLANS.md`](../PLANS.md).

## Purpose / Big Picture

Nexus already stages real macOS app windows into the shell viewport, but the current shell can only clip its own SwiftUI placeholders. The actual app windows remain fully visible anywhere the layout engine keeps them onstage. After this change, the focused slot still uses its full configured width, while the immediate previous and next neighbors remain live only as thin edge slivers. The user should be able to move left and right through the strip, keep the active app centered even at the ends, and see the neighbors partially peek without exposing the rest of their windows.

The visible proof is a workspace with three staged apps: the middle app is dominant, the left and right neighbors show only a thin live strip, and the first and last slots still center because the strip now uses virtual end padding.

## Progress

- [x] (2026-03-13 19:15Z) Refresh `working_list.md` for the edge-sliver strip milestone.
- [x] (2026-03-13 19:15Z) Add this ExecPlan for the edge-sliver strip implementation.
- [x] (2026-03-13 19:09Z) Extend shared layout types and the strip layout engine for virtual padding, revealed fragments, and occlusion bands.
- [x] (2026-03-13 19:09Z) Update visibility planning and choreography to keep only the active slot plus immediate neighbors live.
- [x] (2026-03-13 19:09Z) Add stage-lane mask windows and wire them to viewport movement in the app environment.
- [x] (2026-03-13 19:09Z) Update StageChrome placeholder rendering to match the real reveal aperture.
- [x] (2026-03-13 19:09Z) Add and run automated tests for layout, visibility, choreography, and StageChrome metrics.
- [x] (2026-03-13 19:09Z) Update docs and developer notes with the new mask-based shell behavior.

## Surprises & Discoveries

- Observation: The current shell window already owns the sidebar, topbar, headers, and strip indicator outside the staged app lane.
  Evidence: `WindowChoreographyService` stages real windows below the slot header and above the strip indicator, so only the stage lane needs new overlay masks.
- Observation: The sliver feature did not require replacing the whole visible shell with new interactive overlay windows.
  Evidence: the implementation was able to keep the existing SwiftUI shell window unchanged for chrome and add only passive floating mask windows through `StageMaskCoordinator`.

## Decision Log

- Decision: Keep the existing main shell window and add passive stage-lane mask windows above the staged apps instead of replacing the whole shell with interactive overlay windows.
  Rationale: the current shell already renders the interactive chrome outside the real app lane, so the missing capability is only occluding the visible parts of neighboring app windows.
  Date/Author: 2026-03-13 / Codex
- Decision: Define `visibleSlotIDs` for edge-sliver mode as the active slot plus at most one immediate neighbor on each side.
  Rationale: that is enough to produce live slivers while keeping parked-window behavior simple and avoiding unnecessary extra staged windows behind the shell masks.
  Date/Author: 2026-03-13 / Codex

## Outcomes & Retrospective

The strip now supports centered end slots, thin live neighbor slivers, and shell-owned occlusion bands without changing the underlying slot widths. `StripLayoutEngine` computes padded content width, `revealedFragments`, and `occlusionBands`; `StageChromeView` uses those bands to keep the placeholder stage honest; and `StageMaskCoordinator` turns the same bands into passive floating AppKit windows above the real app lane.

The app environment now fans the latest layout state to both choreography and the mask coordinator, so moving the Nexus shell updates the real windows and the shell occlusion in the same flow. `rtk swift test` passed after adding layout, choreography, and mask-coordinator coverage.

## Context and Orientation

The relevant layout and choreography flow currently starts in `Sources/StageChrome/StageChromeView.swift`, where the selected workspace is converted into a `LayoutPlan` from `Sources/LayoutEngine/StripLayoutEngine.swift`. That plan flows through `Sources/NexusApp/AppEnvironment.swift` into `Sources/NexusApp/WindowChoreographyService.swift`, which stages real app windows by Accessibility frame writes. The shared model types that describe the strip live in `Sources/SharedTypes/DomainModels.swift`, and parking or reveal decisions live in `Sources/VisibilityEngine/VisibilityCoordinator.swift`.

Today the strip uses a centered `scrollOffset`, but it still treats any geometry intersecting the viewport as visible. That means the shell can dim or clip placeholder cards in SwiftUI, yet the real app windows remain fully visible. This plan adds two pieces of model data that both the shell and the choreographer can share: revealed fragments, which are the parts of staged slots that should remain visible, and occlusion bands, which are the areas Nexus must cover with its own mask windows.

## Plan of Work

First, extend the shared strip model so `LayoutPlan` can describe virtual edge padding, revealed slot fragments, and occlusion bands in stage coordinates. Then update the layout engine to center the active slot using dynamic leading and trailing padding based on the first and last slot widths, keep only the active slot plus immediate neighbors live, and compute thin edge peeks for those neighbors.

Next, update visibility planning and choreography so immediate sliver neighbors stay fully staged while farther slots park. The real windows must keep their full strip widths and positions; only the shell masks hide most of the neighboring content.

After the model is correct, add an AppKit coordinator in `Sources/NexusApp` that receives the latest `LayoutPlan` and stage viewport frame and positions a small set of borderless mask windows above the real app lane. Those windows should ignore mouse events so clicks and scrolls continue to reach the underlying app windows.

Finally, update the SwiftUI placeholder stage to render the same reveal aperture, then add automated tests and refresh the architecture and developer notes.

## Concrete Steps

From the repository root:

    rtk swift test

During implementation, re-run:

    rtk swift test
    rtk proxy bash ./scripts/dev-run.sh

The expected app behavior is a centered active slot, thin live neighbor peeks, and passive masks that move with the Nexus window.

## Validation and Acceptance

Run `rtk swift test` and expect the layout, visibility, StageChrome, and app choreography tests to pass. Then run `rtk proxy bash ./scripts/dev-run.sh` and verify a three-slot workspace. The middle slot should show fully, the immediate left and right neighbors should appear only as thin slivers, the first and last slots should still center with empty gutter on the missing-neighbor side, and moving the Nexus window should keep the masks aligned with the staged real windows.

## Idempotence and Recovery

These changes are additive and can be validated repeatedly with `rtk swift test` and `rtk proxy bash ./scripts/dev-run.sh`. If mask windows misbehave during development, temporarily disable the new coordinator wiring in `AppEnvironment` and keep the underlying padded layout and visibility tests as the recovery checkpoint.

## Artifacts and Notes

The key implementation files for this milestone are:

    Sources/SharedTypes/DomainModels.swift
    Sources/LayoutEngine/StripLayoutEngine.swift
    Sources/VisibilityEngine/VisibilityCoordinator.swift
    Sources/NexusApp/WindowChoreographyService.swift
    Sources/NexusApp/AppEnvironment.swift
    Sources/NexusApp/NexusApp.swift
    Sources/StageChrome/StageChromeView.swift
    Tests/LayoutEngineTests/LayoutEngineTests.swift
    Tests/VisibilityEngineTests/VisibilityCoordinatorTests.swift
    Tests/NexusAppTests/WindowChoreographyServiceTests.swift

## Interfaces and Dependencies

In `Sources/SharedTypes/DomainModels.swift`, define:

    public enum RevealedSlotFragmentKind: String, Codable, Sendable, CaseIterable
    public struct RevealedSlotFragment: Codable, Equatable, Identifiable, Sendable

Extend `StageGeometry` with:

    public var edgePeekWidth: Double

Extend `LayoutPlan` with:

    public var leadingPadding: Double
    public var trailingPadding: Double
    public var revealedFragments: [RevealedSlotFragment]
    public var occlusionBands: [RectValue]

`WindowChoreographyService` must keep staging real windows to the full `slotLayouts` frames. The new mask coordinator depends on `LayoutPlan.occlusionBands` and the stage viewport frame to position its passive AppKit windows.
