# NEXUS AGENTS DOCUMENT

## ExecPlans

When writing complex features or significant refactors, use an ExecPlan (as described in `.docs/PLANS.md`) from design to implementation. Write new plans to `.docs/exec/`. If inside Plan Mode, create the plan in a multiline markdown block, and write it after initiating implementation, so you can use the plan to guide your implementation and refer back to it as needed. If outside Plan Mode, you can write the plan directly and refer to it as needed.

## Rule

Always prefix shell commands with `rtk`.

Examples:

```bash
rtk git status
rtk cargo test
rtk npm run build
rtk pytest -q
rtk proxy <cmd>     # Run raw command without filtering
```

## RTK Verification

```bash
rtk --version
rtk gain
which rtk
```

## Development Details

Whenever new updates are made, this file (`AGENTS.md`) should be updated with any surprising files not apparent from the codebase that could benefit other developers. Focus on the why and when it could be useful.

- `scripts/dev-build.sh` and `scripts/dev-run.sh` must invoke sibling shell scripts through `rtk proxy bash ...`, not plain `rtk ...`. This matters whenever you validate the documented CLI workflow because the local `rtk` wrapper only executes raw shell commands through `proxy`, and direct nested script calls fail with misleading command or permission errors.
- `scripts/dev-reset-accessibility.sh` clears the current TCC Accessibility grant for the Nexus bundle ID, and `scripts/dev-run.sh` can invoke it when `NEXUS_RESET_ACCESSIBILITY_ON_START=1` is set. Use this when macOS appears stuck on a stale Accessibility entry after rebuilds; do not enable it for every normal run unless you intentionally want to re-grant permission each time.
- `project.yml` is the source of truth for `Nexus.xcodeproj`. Regenerate the checked-in Xcode project with `rtk proxy bash ./scripts/dev-generate-xcodeproj.sh` whenever you add or rename targets, schemes, or build settings; editing the `.xcodeproj` by hand will drift from the package layout.
- `project.yml` also has to be regenerated when new source files are added under app-owned groups like `Sources/NexusApp/`. If Xcode builds fail with "cannot find <type> in scope" right after a new app file lands, regenerate `Nexus.xcodeproj` before debugging the Swift code because the checked-in project can simply be missing the file reference.
- `scripts/make-app-bundle.sh`, `scripts/dev-build.sh`, and `scripts/dev-run.sh` now treat `NEXUS_CODESIGN_IDENTITY` as the default-required signing input for TCC-sensitive runs and install to `~/Applications/Nexus.app` unless `NEXUS_DEV_INSTALL_PATH` is set. Check these scripts first whenever Accessibility appears "stuck denied" after rebuilds, because stable signing identity and stable launch path are now part of runtime correctness, not just packaging.
- The `NexusApp` Xcode target mirrors the CLI install flow via a post-build script: when Xcode signing is configured, it copies the signed app to `~/Applications/Nexus.app` (or `NEXUS_DEV_INSTALL_PATH`), writes `dev-build-metadata.json` only if standalone `codesign` can reuse the selected identity, and otherwise falls back to installing the already-signed Xcode product unchanged. Inspect `project.yml` first when Xcode builds fail in `PhaseScriptExecution` or diagnostics shows `unknown` build identity after an Xcode run, because the install script now deliberately skips metadata injection when the selected signing mode is not reusable outside Xcode.
- `NEXUS_CODESIGN_IDENTITY` must also resolve through `security find-identity -v -p codesigning`. A generic self-signed certificate name is not enough; if the identity is missing from that list, the bundle may sign but macOS TCC can still refuse to persist Accessibility trust for it.
- `NEXUS_ALLOW_ADHOC=1` is explicit fallback only. Use it for non-TCC debugging when needed, but expect unreliable Accessibility trust persistence for generic AX choreography if you run ad-hoc builds.
- `Sources/NexusApp/WindowChoreographyService.swift` is the app-layer bridge from `StageChrome` layout updates to real AX window mutations. It is the first place to inspect when workspace or slot changes update the sidebar and strip state correctly but fail to move or reveal native windows, because the SwiftUI views still only compute layout while the actual staging, parking, and launch fallback now live there.
- `Sources/Diagnostics/DiagnosticsCenter.swift` now combines permission inspection with runtime build identity metadata, and `Sources/StageChrome/StageChromeView.swift` surfaces that metadata in diagnostics UI. Inspect these files when users report "Accessibility granted in System Settings but Nexus still says denied," because they now differentiate true trust denial from ad-hoc/path identity drift.
- `Sources/NexusApp/WindowChoreographyService.swift` now stages every `LayoutPlan.visibleSlotIDs` window before issuing one final focus handoff to the active slot, but the AX Y coordinate must still be converted from AppKit's bottom-origin screen space into Accessibility's top-origin per-screen space. Check this file first when visible neighbor apps stage at the correct width but land vertically offset, or when non-active visible windows stay behind the shell because the raise pass did not run.
- `Sources/NexusApp/AppEnvironment.swift` is now the ordering gate for live choreography. It coalesces pending layout updates and applies only the latest request serially, which matters whenever slot focus, workspace switches, or strip relayout appear to "flash then revert" because the failure may be stale layout delivery rather than AX mutation itself.
- `Sources/NexusApp/StageMaskCoordinator.swift` owns the passive floating mask windows that hide non-focused neighbor content inside the stage lane while still letting mouse and scroll input pass through to the revealed app regions. Inspect it first when edge slivers are the wrong width, masks drift after moving Nexus, or the shell seems to block app input in the viewport.
- `Sources/NexusApp/AppEnvironment.swift` also stores the latest `(workspace, layout)` context and folds the integral stage viewport frame into the choreography signature. Inspect it whenever staged windows follow slot changes correctly but do not move when the Nexus window itself is dragged or resized, because pure viewport-motion replay now happens there instead of in `StageChromeView`.
- `Sources/NexusApp/AppEnvironment.swift` now also runs the native reverse-focus loop. Inspect it first when clicking a real app window does not update the selected Nexus slot, or when Nexus navigation seems to bounce back to the same window immediately afterward, because the focused-window polling loop, fingerprint dedupe, and short suppression window all live there.
- `Sources/NexusApp/WindowChoreographyService.swift` and `Sources/NexusApp/AppEnvironment.swift` now treat denied Accessibility as an explicit blocked choreography outcome for generic external-window slots. Check these files when users see status changes but no window movement, because app-only activation fallback should no longer masquerade as successful staging.
- `Sources/NexusApp/WindowSlotMatcher.swift` is now the shared forward and reverse rematching heuristic. Check it whenever a native click highlights the wrong slot, an unmatched app incorrectly steals Nexus selection, or same-bundle apps become ambiguous, because both choreography candidate resolution and reverse focus sync now depend on the same scoring rules.
- `Sources/NexusApp/WindowSlotMatcher.swift` also now accepts an optional preferred-workspace tie-break for reverse focus. Use that path when the same live app process is intentionally duplicated across workspaces, because Nexus will otherwise treat equal-scored matches as ambiguous and ignore the click rather than guessing between two slots bound to the same PID.
- When reverse focus behaves inconsistently for only some apps, probe from the trusted Nexus path before changing heuristics. In practice that means: 1. inspect `~/Library/Application Support/Nexus/workspace-state.json` for duplicate `runtimeBinding.processID` or `windowID` values across workspaces, and 2. stream Nexus’s own `focusSync` logs with `rtk log stream --style compact --level debug --predicate 'subsystem == "dev.nexusniri.Nexus" AND category == "focusSync"'` while clicking the live windows. A standalone Swift or AX probe launched from the shell can return `nil` focused elements because that helper process is not itself Accessibility-trusted, so it is a poor source of truth compared with the signed Nexus app.
- `Sources/StageChrome/StageChromeView.swift` now has `ReporterView` listening to `NSWindow.didMove`, `didResize`, `didChangeScreen`, and `didEndLiveResize` notifications instead of relying on view layout alone. This is the first place to inspect when visible-slot choreography works on slot switches but not when the user drags the Nexus window, because the live-follow trigger is screen-space reporting rather than the AX bridge.
- `Sources/WindowRegistry/AXWindowRegistry.swift` must not assume `AXWindowNumber` exists. On current macOS builds, apps like Zen, Zed, and VS Code can expose AX windows with no `AXWindowNumber`, so selection has to prefer the focused/main `AXUIElement` and standard-window heuristics. This is the first place to inspect when focus works at the app level but resize or move appears to hit the wrong window or no-op entirely.
- `Sources/WindowRegistry/AXWindowRegistry.swift` now exposes `focusedWindowCandidate()` using the system-wide focused application and focused window AX attributes instead of rescanning every window on each poll. Use that path first when reverse focus sync feels stale or expensive, because the polling loop is intentionally built around the direct focused-window fast path.
- `Sources/WindowRegistry/AXWindowRegistry.swift` also needs the system-wide `kAXFocusedUIElementAttribute` path for Electron-style apps that leave `kAXFocusedWindowAttribute` empty, and `Sources/NexusApp/WindowSlotMatcher.swift` strips `.helper` bundle suffixes before matching. Check those files first when Zed or Zen follow focus but VS Code or another helper-hosted app does not, because the focused element may belong to a helper process while the slot is bound to the main app bundle.
- `Sources/WindowRegistry/FocusedWindowAttribution.swift` is now the pure helper that decides whether reverse focus should keep the focused process, remap helper-owned content to the frontmost host app, or ignore the event entirely. Check it together with `Sources/WindowRegistry/AXWindowRegistry.swift` when apps like Zen or Tether activate correctly on click but Nexus does not follow them, because helper-owned web content should now resolve through the host app only if that host exposes a standard window.
- `Tests/WindowRegistryTests/FocusedWindowAttributionTests.swift` locks the Zen plugin-container and Tether SafariPlatformSupport-helper cases at the ownership-attribution layer. Extend those tests before adding any new helper-bundle canonicalization in `WindowSlotMatcher`, because the intended fix path is host-app attribution rather than broad bundle rewrites.
- `Sources/WindowRegistry/AXWindowRegistry.swift` now activates the target app without `.activateAllWindows`, then raises only the chosen window after optional `AXMain` or `AXFocused` writes. Check this file when switching slots keeps Nexus in front, or when focusing one visible app drags every window from that app above the shell, because the activation options determine whether the app or just the target window comes forward.
- `Sources/NexusApp/AppDelegate.swift` should not aggressively frontmost the Nexus app on launch. Check it first if Nexus starts behaving like an always-on-top shell even before any choreography runs.
- `Sources/StageChrome/StageChromeView.swift` no longer implements the shell strip as a horizontal `ScrollView`. The v1 strip is now a clipped overlay driven entirely by `LayoutPlan.scrollOffset`, with `StageSurfaceView` rendering dimmed slot presence and `SlotHeaderStripView` owning the only direct strip click targets. Inspect this file first when centering, dimming, or indicator movement is wrong even though workspace state is updating correctly.
- `Sources/StageChrome/ChromeTheme.swift` uses `ChromeMetrics.stageGeometry(for:)` to re-inflate sidebar and topbar dimensions from the visible viewport measured by `StageChromeView`'s `GeometryReader`. This matters whenever layout math looks offset or under-sized, because the layout engine still expects full chrome-aware `StageGeometry` rather than the already-clipped content size.
- `Sources/LayoutEngine/StripLayoutEngine.swift` now computes `leadingPadding`, `trailingPadding`, `revealedFragments`, and `occlusionBands` in addition to the full strip frames. Check it first when the first or last slot stops centering, immediate neighbors peek at the wrong width, or mask bands leave visible gaps that do not match the shell placeholder stage.

## Sub Agents

Use sub-agents where appropriate to break down complex changes into manageable pieces, and to allow for more focused implementation and testing. For example, if implementing a new feature that requires both backend and frontend changes, you might create separate sub-agents for each layer of the stack, but before then use an exploring agent (or multiple) to get context on the codebase and research the best approaches for the feature, outline the specific steps needed for implementation into a final exec plan, and spin up task subagents that handle the implementation. This allows for more efficient development and testing, as each sub-agent can focus on a specific aspect of the implementation, and can be tested independently before being integrated into the larger codebase.

## Final Output

When asking the user to verify implemented changes, output a checklist they can fill to make sure everything works as intended. Describe what they should see, how it should work, and what they need to manually test. The user will then fill in the checklist and provide feedback on any issues they encounter, which can be used to further refine the implementation.

If the user asked for multiple changes and only some were implemented, make sure to clearly indicate which ones were completed, which ones were not fully realized, and which ones are still pending. For example:

```txt
- [x] Implement app scaffold (completed with basic layout and navigation)
- [~] Implement feature A (stub implementation completed)
- [ ] Implement feature B (pending due to X reason)
```

Include a commit message after each implementation or fix, following the Conventional Commits specifications. If it's a large change, follow this format:

```txt
feat(update): add startup update prompt choices and sectioned changelog pipeline
- feat(update): gate startup updates behind user choice (Yes/No/Remind Later)
- feat(update): persist per-release prompt decisions (ignore until newer, 24h remind-later)
- refactor(update): split updater flow into eligibility check and install phases
- feat(update): parse GitHub release body into sectioned changelog blocks for in-app prompt
- test(update): add updater decision/state-store/changelog parser coverage
- feat(ci): generate release notes sections from commit metadata and publish via body_path
- feat(ci): support multi-section changelog from Conventional Commit lines in commit body
- fix(navigation): clamp bottom navbar sizing to prevent tiny rendering on some phones
- fix(navigation): make top-level tab swipe detection more reliable in Explore
- fix(search): move Explore apply+navigate to app scope to prevent canceled loads on slower devices
- docs(readme): document updater prompt behavior and changelog contract
```
