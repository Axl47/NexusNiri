# Working List
## In Progress
- [x] Implement host-app reverse focus attribution in `WindowRegistry`

## Pending
- [x] No open items for this slice

## Done
- [x] Resolve duplicate-process reverse-focus ambiguity for Zen and Tether by preferring the currently selected workspace when reverse matching ties across workspaces
- [x] Add ownership-attribution unit coverage in `Tests/WindowRegistryTests`
- [x] Extend reverse-focus app tests and keep matcher regressions green
- [x] Regenerate `Nexus.xcodeproj`, update developer notes, and verify with `rtk swift test` plus unsigned Xcode build
- [x] Update docs and exec notes for native focus-driven reverse orchestration
- [x] Add focused-window discovery and shared slot matching for reverse orchestration
- [x] Thread focus policy through choreography and app environment
- [x] Extend tests for matcher, workspace sync, and reverse focus monitoring
- [x] Verify native focus-driven reverse orchestration with `rtk swift test`
- [x] Regenerate `Nexus.xcodeproj` and verify the unsigned Xcode build after adding the matcher source file

- [x] Refresh the working list for the native focus-driven reverse orchestration milestone
- [x] Add a checked-in XcodeGen-based `Nexus.xcodeproj` workflow so signing and entitlements can be inspected and managed from Xcode without losing the stable installed-app path
- [x] Document and lock the stable local signing workflow (`NEXUS_CODESIGN_IDENTITY` + `~/Applications/Nexus.app`) for Accessibility-sensitive choreography testing
- [x] Document explicit ad-hoc fallback (`NEXUS_ALLOW_ADHOC=1`) and diagnostics messaging for blocked generic choreography when Accessibility is denied
- [x] Implement visible-slot native geometry conformance with live viewport follow
- [x] Locate the active ExecPlan and identify the current milestone from the workspace state
- [x] Reconstruct active task state from the existing ExecPlan and current worktree
- [x] Fix Swift 6 concurrency/build blockers so `rtk swift test` passes
- [x] Repair and verify the CLI bundle flow with `rtk proxy bash ./scripts/dev-build.sh`
- [x] Implement the next live window choreography slice for real workspace transitions
- [x] Update ExecPlan and developer notes with the live choreography slice and reveal-all behavior
- [x] Rewrite `StageChrome` from a horizontal `ScrollView` strip into a focus-driven overlay viewport
- [x] Remove stage-level resize handles and direct strip dragging from the shell UI for the v1 scroll slice
- [x] Add layout, chrome, and workspace navigation coverage for the scroll-behavior rewrite
