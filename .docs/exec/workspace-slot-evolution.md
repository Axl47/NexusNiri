# ExecPlan: Phased Workspace Slot Evolution

This ExecPlan is a living document. When implementation starts, write it to `.docs/exec/workspace-slot-evolution.md` and maintain it in accordance with `.docs/PLANS.md`.

## Purpose / Big Picture

Nexus should move from a starter set of app slots that are effectively fixed by code into a workspace shell where slot order is editable, slots can be added or removed from the live desktop, and opted-in workspaces can automatically absorb newly focused unmanaged windows. The user-visible proof is four staged passes: template-backed starter workspaces, reorderable slots, manual focused-window slot CRUD, and opt-in automatic focused-window capture.

## Summary

The plan keeps `Sources/NexusApp/Resources/default-workspaces.json` as a first-run demo seed, but removes hardcoded slot knowledge from `WorkspaceSession`. New-workspace creation becomes app-layer template driven, slot identity becomes hybrid (`application` for curated starter slots and `window` for captured slots), and the existing focused-window monitor in `AppEnvironment` becomes the final auto-add hook. Every pass ships visible shell controls and matching command-menu coverage.

## Progress

- [x] (2026-03-14 23:30Z) Confirm current architecture, persistence flow, shell UI entry points, matcher behavior, and test baseline.
- [x] (2026-03-14 23:48Z) Pass 1: Externalize new-workspace slot templates and app presets.
- [x] (2026-03-14 23:49Z) Pass 2: Add persistent dynamic slot placement.
- [x] (2026-03-14 23:50Z) Pass 3: Add manual focused-window slot add/remove.
- [x] (2026-03-14 23:50Z) Pass 4: Add per-workspace opt-in automatic focused-window capture.
- [x] (2026-03-14 23:51Z) Run `rtk swift test` and regenerate `Nexus.xcodeproj`.

## Surprises & Discoveries

- Observation: bundled first-run workspaces are already JSON-backed in `Sources/NexusApp/AppBootstrap.swift`; the main remaining hardcoding is the fixed three-slot `addWorkspace` path in `Sources/WorkspaceEngine/WorkspaceSession.swift`.
- Observation: the shell currently exposes workspace creation plus slot navigation, but no slot CRUD or slot-order editing surface exists in either `Sources/StageChrome/StageChromeView.swift` or `Sources/NexusApp/NexusApp.swift`.
- Observation: the focused-window polling loop in `Sources/NexusApp/AppEnvironment.swift` already yields the exact safe trigger for the final automation pass; unmatched windows currently log and no-op.
- Observation: `Sources/NexusApp/WindowSlotMatcher.swift` already has the right shape for a hybrid model, but bundle-only fallback must be disabled for window-targeted slots.
- Observation: explicit "add focused window" cannot safely query the currently frontmost window after a Nexus chrome click because Nexus becomes frontmost first.
  Evidence: final implementation stores the last externally focused candidate in `AppEnvironment` and reuses it for manual add, while auto-add still operates on the live focus callback.

## Decision Log

- Decision: keep `default-workspaces.json` as the first-run demo state and do not migrate existing persisted workspaces in pass 1.
  Rationale: this bounds the first pass to removing code hardcoding rather than rewriting bootstrap or user state.
  Date/Author: 2026-03-14 / Codex
- Decision: introduce a hybrid slot targeting mode with `.application` and `.window`.
  Rationale: it matches the requested window-first add flow while keeping starter slots and future stacked-slot work compatible.
  Date/Author: 2026-03-14 / Codex
- Decision: automatic capture is opt-in per workspace and is triggered by focused standard windows only.
  Rationale: this is the safest behavior on top of the existing focus monitor and avoids noisy background-window ingestion.
  Date/Author: 2026-03-14 / Codex
- Decision: dynamic placement in this iteration is explicit move-left and move-right, not drag-and-drop.
  Rationale: the current shell already has deterministic slot selection and clipped strip rendering; move commands add less UI risk than drag semantics.
  Date/Author: 2026-03-14 / Codex
- Decision: manual add and auto-add must refuse exact-window duplicates across all workspaces.
  Rationale: allowing the same live window to be managed by multiple workspaces would destabilize reverse focus and choreography.
  Date/Author: 2026-03-14 / Codex
- Decision: manual add should capture the last externally focused window instead of re-querying the current frontmost window at button-click time.
  Rationale: clicking Nexus chrome for the add action makes Nexus frontmost, which would otherwise cause the add flow to capture the shell itself or nothing useful.
  Date/Author: 2026-03-14 / Codex

## Outcomes & Retrospective

All four passes landed in a single implementation slice. New-workspace creation is now driven by resource-backed presets and templates, slot order is mutable and persisted, focused-window slot add/remove is available from both shell chrome and command menus, and selected workspaces can opt into automatic focused-window capture. The acceptance proof matched the intended behavior through automated coverage and a full `rtk swift test` pass; stacked-slot UI and assignment-rule automation remain intentionally deferred.

## Context and Orientation

`Sources/SharedTypes/DomainModels.swift` defines persisted workspace and slot data. `Sources/WorkspaceEngine/WorkspaceSession.swift` owns mutation and persistence, including the current hardcoded new-workspace slot trio. `Sources/NexusApp/AppEnvironment.swift` boots the session from `AppBootstrap.defaultWorkspaces()`, runs the focused-window monitor, and is the orchestration point for new slot creation in passes 3 and 4. `Sources/NexusApp/WindowSlotMatcher.swift` maps live windows back to slots, which is central both for reverse focus and for duplicate detection before new slot creation. `Sources/StageChrome/StageChromeView.swift` and `Sources/NexusApp/NexusApp.swift` are the user-facing validation surfaces and must stay in sync for both windowed and notch-fill shell branches.

## Interfaces and Dependencies

Add `SlotTargetingMode` to `SharedTypes` with cases `.application` and `.window`, and store it on `Slot` with backward-compatible decoding defaulting to `.application`. Add `AutoAddPolicy` to `SharedTypes` with cases `.disabled` and `.focusedStandardWindow`, and store it on `Workspace` with backward-compatible decoding defaulting to `.disabled`. Keep `SlotKind` unchanged.

Replace the hardcoded creation logic in `WorkspaceSession.addWorkspace(named:)` with a generic session API: `addWorkspace(_ workspace: Workspace)`, `addSlot(_ slot: Slot, to workspaceID: String, afterSlotID: String?, selecting: Bool, origin: SelectionOrigin)`, `removeSelectedSlot()`, and slot-order APIs `moveSelectedSlotLeft()`, `moveSelectedSlotRight()`, plus an internal/general `moveSlot(id:in:to:)`. These methods must own selection fallback, `slotOrder` updates, `layoutState.activeIndex` recomputation, timestamps, and persistence.

Add app-layer resource loaders in `Sources/NexusApp/` for `slot-presets.json` and `workspace-templates.json`. `slot-presets.json` is keyed by bundle ID and supplies default label, `SlotKind`, width policy, layout role, warm preference, and optional adapter metadata. `workspace-templates.json` defines starter workspace templates for `starter`, `api`, and `ui` in pass 1, then adds `blank` in pass 3. Template instantiation must mint fresh workspace and slot IDs and fresh timestamps on every creation.

Add a single app-layer `FocusedWindowSlotFactory` that converts a `WindowCandidate` plus slot preset into a new `Slot`. It must create `.window` slots for focused-window capture, use `.externalWindow` as the generic default, upgrade to `.hybrid` plus `adapterID: "tether"` when the preset says so, seed `AppBinding.bundleID`, seed `AppBinding.titleHints` from normalized title segments, and populate `runtimeBinding` from the captured candidate.

## Plan of Work

### Pass 1: Externalize new-workspace slot templates and enabled-app presets

Create `Sources/NexusApp/Resources/slot-presets.json`, `Sources/NexusApp/Resources/workspace-templates.json`, and app-layer loaders such as `SlotPresetCatalog.swift` and `WorkspaceTemplateCatalog.swift`. Remove the fixed Editor/Zen/Tether constructor from `WorkspaceSession` and make `AppEnvironment` own workspace creation by instantiating a chosen template and passing the finished `Workspace` into the session. Update the sidebar plus control in both shell variants to present a small workspace-template menu, and mirror the same creation actions in the `Workspace` command menu in `Sources/NexusApp/NexusApp.swift`. Keep `default-workspaces.json` as-is for first-run demos.

### Pass 2: Add dynamic slot placement

Add reorder operations to `WorkspaceSession` and make them persist purely by rewriting `slotOrder` while keeping the same `activeSlotID`. Update `StageChromeView` so the focused slot header shows move-left and move-right affordances, and add matching `Slots` command-menu actions with `Cmd+Opt+Shift+Left` and `Cmd+Opt+Shift+Right`. Reordering must immediately restage windows through the existing layout path, preserve the active slot, clamp at the ends, and survive relaunch by round-tripping through `workspace-state.json`.

### Pass 3: Add manual focused-window slot add/remove

Add the hybrid slot-targeting model to `SharedTypes` and tighten `WindowSlotMatcher` so `.window` slots never accept bundle-only reverse matches. Add `FocusedWindowSlotFactory` in `Sources/NexusApp/` and a session-level `addSlot` path. The explicit add action must use `windowRegistry.focusedWindowCandidate()`, reject Nexus itself, minimized windows, and nil-bundle candidates, then either select the exact existing managed window or create a new `.window` slot immediately after the current slot. The slot label should use the focused window title when it differs from the app name; otherwise use the app name and append ` 2`, ` 3`, and so on for workspace-local duplicates. Add `removeSelectedSlot()` to the session; removing a slot only unmanages it and must not hide or close the real app window. At this point extend the workspace-template menu with `Blank Workspace`, update empty-state copy to point to the add action, and add topbar plus/minus controls in both shell layouts together with `Slots` menu entries.

### Pass 4: Add per-workspace opt-in automatic focused-window capture

Add `autoAddPolicy` to `Workspace` and surface it as a topbar chip labeled `Auto-add` in both shell layouts plus a matching workspace/menu toggle. In `AppEnvironment.handleFocusedWindowCandidate(_:)`, after the matcher fails to find a slot, check whether the selected workspace has `.focusedStandardWindow`. If not, keep the current ignore behavior. If yes, refuse duplicates across all workspaces, build a `.window` slot with the same factory used in pass 3, insert it after the currently active slot, and mark it selected with origin `.nativeFocusSync` so choreography preserves the already-focused external window. Automatic capture must stay focus-triggered only; it must not diff the entire registry snapshot for background windows.

## Concrete Steps

Work from the repository root. If any new source files are added under app-owned groups, regenerate the checked-in Xcode project with `rtk proxy bash ./scripts/dev-generate-xcodeproj.sh` before validating Xcode workflows.

Run these commands after each pass:
    rtk swift test --filter WorkspaceEngineTests
    rtk swift test --filter WindowSlotMatcherTests
    rtk swift test

Run full manual validation after the pass-specific tests:
    rtk proxy bash ./scripts/dev-run.sh

## Validation and Acceptance

- Pass 1: creating a workspace from the sidebar plus menu or the `Workspace` command menu must create the chosen starter template, persist it, and reload it after relaunch.
- Pass 2: moving the selected slot left or right must visibly reorder the header strip and native staging order immediately, clamp at the strip edges, and remain reordered after relaunch.
- Pass 3: with an unmanaged focused app window, `Add Focused Window` must create a new slot after the current one; removing the selected slot must leave the external window open and select the adjacent slot or empty-state workspace as appropriate.
- Pass 3: focusing a window already managed by an exact `.window` slot must not create a duplicate; Nexus should instead select the existing slot or switch to its workspace.
- Pass 4: when `Auto-add` is off, focusing an unmanaged window must keep the current no-op behavior; when `Auto-add` is on for the current workspace, focusing an unmanaged standard window must create a new slot and keep the external window focused.
- Pass 4: enabling `Auto-add` must not ingest Nexus itself, minimized windows, or exact-window duplicates already managed elsewhere.

## Idempotence and Recovery

These passes mutate persisted workspace state in `~/Library/Application Support/Nexus/workspace-state.json`. Before manual validation, copy that file aside if the existing state matters. To re-test first-run demo seeding, remove or rename the file and relaunch. Slot removal is non-destructive to external apps; it only removes Nexus management metadata. New decoding fields must default cleanly so older persisted state and `default-workspaces.json` continue to load.

## Artifacts and Notes

Do not wire `AssignmentRule` or stacked-slot UI into this slice. The future stack/tab direction is preserved by the hybrid targeting model plus the existing `SlotKind.stacked`, but no multi-window container behavior should land in these passes. Keep `slot-presets.json` small and explicit: include special handling for `com.t3tools.tether`, preserve current starter behavior for VS Code, Zed, and Zen, and use a generic external-window fallback for every other bundle.

## Recommended Commit Cadence

- `refactor(workspace): externalize starter workspace templates and slot presets`
- `feat(slots): support persistent slot reordering`
- `feat(slots): add focused-window slot capture and removal`
- `feat(workspace): auto-add focused unmanaged windows in opted-in workspaces`

## Assumptions and Defaults

- Auto-add means “the first time an unmatched focused standard window becomes active while the current workspace toggle is enabled,” not “diff every new background window.”
- Explicit add and auto-add always insert after the current active slot; if the workspace is empty, they insert at index `0`.
- `.application` slots may keep the existing bundle-plus-title matching behavior; `.window` slots require stronger evidence and never accept bundle-only matches.
- The first stacked-slot or tabbed-slot feature is out of scope for these passes; future work should build on `SlotTargetingMode`, not replace it.

Revision note (2026-03-14): updated this ExecPlan after implementation to record the completed pass status, the last-observed-external-window decision for manual add, and the successful verification path.
