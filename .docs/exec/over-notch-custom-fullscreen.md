# Add Nexus Over-Notch Custom Fullscreen

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with `.docs/PLANS.md`.

## Purpose / Big Picture

Nexus currently uses a standard hidden-title window whose usable stage area always sits below the menu bar region. After this change, Nexus can enter a custom fullscreen mode that fills the full display frame on MacBook displays with a camera housing, uses the left and right notch lobes for shell chrome, and keeps staged app content inside the safe content region below the camera housing. The behavior is Nexus-owned and does not rely on SIP changes, code injection, or macOS fullscreen Spaces.

## Progress

- [x] (2026-03-13 23:55Z) Created this ExecPlan and refreshed `working_list.md` for the implementation.
- [x] (2026-03-14 00:14Z) Implemented shared shell-presentation types in `Sources/SharedTypes/DomainModels.swift` and added `Sources/NexusApp/ShellWindowManager.swift`.
- [x] (2026-03-14 00:22Z) Wired shell mode persistence, shell layout propagation, and the over-notch command through `Sources/NexusApp/AppEnvironment.swift` and `Sources/NexusApp/NexusApp.swift`.
- [x] (2026-03-14 00:32Z) Refactored `Sources/StageChrome/StageChromeView.swift` and `Sources/StageChrome/ChromeTheme.swift` for notch-fill rendering with a full safe-content viewport.
- [x] (2026-03-14 00:37Z) Updated stage masks, automated tests, `AppResources/Info.plist`, and `AGENTS.md`.
- [x] (2026-03-14 01:01Z) Regenerated `Nexus.xcodeproj` and reran the full Swift package test suite.

## Surprises & Discoveries

- Observation: `StageChrome` and `NexusApp` cannot share new shell-presentation types if they live in the app target because `StageChrome` is a lower-level package target.
  Evidence: `Package.swift` makes `NexusApp` depend on `StageChrome`, not the reverse, so shared shell-presentation value types have to live in `SharedTypes`.

- Observation: `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea` are optional on the current SDK, not guaranteed rectangles.
  Evidence: `ShellWindowManager.swift` needed explicit optional normalization before the notch-lobe frames could be stored in `ShellDisplayLayout`.

## Decision Log

- Decision: Put `ShellPresentationMode` and `ShellDisplayLayout` in `Sources/SharedTypes/DomainModels.swift`.
  Rationale: both `StageChrome` and `NexusApp` need to compile against the same model, and `SharedTypes` is the existing dependency boundary they both import.
  Date/Author: 2026-03-13 / Codex

## Outcomes & Retrospective

The feature is functionally implemented in the Swift package targets. Nexus now owns a persisted `ShellPresentationMode`, can switch into a borderless over-notch shell mode without using macOS fullscreen Spaces, reports a full safe-content stage viewport in that mode, and renders compact chrome in the leading and trailing top regions instead of charging the old sidebar/topbar tax against the layout engine.

The feature is fully landed in both the Swift package and the checked-in Xcode project. `Nexus.xcodeproj` has been regenerated so Xcode picks up `Sources/NexusApp/ShellWindowManager.swift`, and the package-wide verification pass stayed green after the project metadata update.

## Context and Orientation

`Sources/NexusApp/NexusApp.swift` creates the main shell scene and already routes shell-window attachment events into `AppEnvironment` using `onShellWindowChanged`. `Sources/NexusApp/AppEnvironment.swift` owns shell lifecycle state, stage viewport frame delivery, and stage mask coordination. `Sources/StageChrome/StageChromeView.swift` currently assumes a fixed sidebar-plus-topbar shell layout and reports the stage viewport frame through `ScreenSpaceFrameReporter`. `Sources/NexusApp/StageMaskCoordinator.swift` positions passive child windows that hide native content behind shell chrome.

The new fullscreen behavior needs one AppKit-specific helper that can mutate the owned Nexus window and compute safe-content geometry from `NSScreen`. The resulting shell geometry then needs to flow back down into `StageChromeView` as value data so the SwiftUI tree can render the correct notch-aware layout.

## Plan of Work

Add shared value types for shell mode and shell display layout, including helpers for converting the screen-space frames into window-local frames used by SwiftUI. Add a new `ShellWindowManager` in `Sources/NexusApp/` that saves the pre-fullscreen window state, applies the borderless frame-filling mode, restores windowed state, and computes a `ShellDisplayLayout` from `NSScreen.frame`, `safeAreaInsets`, and the auxiliary notch areas.

Then extend `AppEnvironment` to own the persisted shell mode, load and save it through `UserDefaults`, apply the current mode whenever the shell window attaches or changes screens, and keep `shellDisplayLayout` synchronized with `StageMaskCoordinator`. Pass that state through `NexusApp` into `StageChromeView`.

Finally, refactor `StageChromeView` so notch-fill mode renders the stage viewport inside the safe content frame while rendering compact shell chrome in the left and right notch lobes. Update masks, tests, `Info.plist`, and `AGENTS.md`, then run targeted verification.

## Concrete Steps

From `/Users/axel/Desktop/Code_Projects/Personal/NexusNiri`, use:

    rtk swift test --filter StageChromeTests
    rtk swift test --filter NexusAppTests

If targeted filtering is unavailable in the active toolchain, run:

    rtk swift test

## Validation and Acceptance

Acceptance requires automated proof that the shell mode value types and geometry helpers behave correctly for windowed and notch-fill layouts, and that app-environment persistence restores the expected shell mode. Manual acceptance requires toggling over-notch mode on a notched MacBook, confirming chrome occupies the left and right notch lobes, verifying staged app content stays below the camera housing, and confirming the chosen mode is restored on relaunch.

## Idempotence and Recovery

The change is additive and safe to retry. If the borderless shell mode misbehaves during development, force `AppEnvironment` back to `.windowed` and keep the shared types plus tests as the stable checkpoint while debugging the AppKit-specific helper.

## Artifacts and Notes

The plan is based on Apple’s documented distinction between system fullscreen and custom fullscreen: `NSScreen.safeAreaInsets` applies to custom fullscreen, while `toggleFullScreen(_:)` stays inside the safe area automatically.

Targeted verification already completed against the Swift package:

    rtk swift test --filter StageChromeTests
    rtk swift test --filter NexusAppTests

Observed result:

    ✔ StageChromeTests: 6 tests passed.
    ✔ NexusAppTests: 33 tests passed.
    ✔ Full package suite: 71 tests passed.

## Interfaces and Dependencies

Add these shared interfaces:

    public enum ShellPresentationMode: String, Codable, Sendable {
        case windowed
        case notchFill
    }

    public struct ShellDisplayLayout: Codable, Equatable, Sendable {
        public var windowFrame: CGRect
        public var safeContentFrame: CGRect
        public var topLeftAuxiliaryFrame: CGRect?
        public var topRightAuxiliaryFrame: CGRect?
        public var hasCameraHousing: Bool
    }

Add this app-layer protocol in `Sources/NexusApp/ShellWindowManager.swift`:

    @MainActor
    protocol ShellWindowManaging {
        func attach(window: NSWindow?)
        func apply(mode: ShellPresentationMode, screen: NSScreen?)
        func currentLayout() -> ShellDisplayLayout?
    }

Plan note: updated on 2026-03-14 after implementation to record the shipped architecture, optional auxiliary-notch-area discovery, the Xcode project regeneration, and the final package-wide verification result.
