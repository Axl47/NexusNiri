# Working List
## Pending
- [ ] Harden workspace rematching and runtime binding persistence across live multi-workspace switches

## Done
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
