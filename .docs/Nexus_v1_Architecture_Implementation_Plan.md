# Nexus v1 Architecture & Implementation Plan
_Last updated: March 12, 2026_


## How to use this document

This document is meant to be handed to a developer or used as the base architecture brief for coding agents. It is intentionally written at the system-design level rather than the implementation-detail level. The recommended workflow is:

1. Use Sections 1–6 to align on product intent and boundaries.
2. Use Sections 7–20 to define subsystem ownership and technical approach.
3. Use Sections 21–23 to plan delivery scope and phase sequencing.
4. Use Sections 24–29 as the source of truth for data models, behaviors, task breakdown, and testing.
5. Treat Section 31 and the source links as the reference set for future architectural decisions.

## Table of contents

- [1. Executive summary](#1-executive-summary)
- [2. Product vision](#2-product-vision)
- [3. Product boundaries and non-goals](#3-product-boundaries-and-non-goals)
- [4. Core design principles](#4-core-design-principles)
- [5. UX concept and interaction model](#5-ux-concept-and-interaction-model)
- [6. System architecture overview](#6-system-architecture-overview)
- [7. Stage Chrome](#7-stage-chrome)
- [8. Window Registry](#8-window-registry)
- [9. Workspace Engine](#9-workspace-engine)
- [10. Layout Engine](#10-layout-engine)
- [11. Visibility Engine](#11-visibility-engine)
- [12. Focus and input coordination](#12-focus-and-input-coordination)
- [13. Adapter Bus](#13-adapter-bus)
- [14. App strategy by category](#14-app-strategy-by-category)
- [15. Owned surfaces vs external surfaces](#15-owned-surfaces-vs-external-surfaces)
- [16. Persistence and configuration](#16-persistence-and-configuration)
- [17. Safety and recovery](#17-safety-and-recovery)
- [18. Observability and diagnostics](#18-observability-and-diagnostics)
- [19. Permissions model](#19-permissions-model)
- [20. Multi-display model](#20-multi-display-model)
- [21. MVP scope definition](#21-mvp-scope-definition)
- [22. Phase plan](#22-phase-plan)
- [23. Post-MVP direction](#23-post-mvp-direction)
- [24. Data model](#24-data-model)
- [25. MVP algorithms and behaviors](#25-mvp-algorithms-and-behaviors)
- [26. Agent-oriented delivery plan](#26-agent-oriented-delivery-plan)
- [27. Testing strategy](#27-testing-strategy)
- [28. Risk register](#28-risk-register)
- [29. Recommended first implementation slice](#29-recommended-first-implementation-slice)
- [30. Final recommendations](#30-final-recommendations)
- [31. Reference notes and external inspiration](#31-reference-notes-and-external-inspiration)
- [32. Source links](#32-source-links)


## 1. Executive summary

Nexus should be built as a **macOS spatial shell over real application windows**, not as a traditional tiling window manager and not as a host that tries to truly embed third-party native windows. The product goal is to make Nexus the place where project context lives: workspaces, app ordering, layout memory, switching, state restoration, and fast navigation all belong to Nexus, while the actual editor, browser, terminal, and agent tools remain the real apps the user already trusts and uses.

This plan reflects the core constraints and decisions we already established:

- Nexus should **not** try to replace every app with an internal clone.
- Nexus should **reuse the real apps** the user already uses, especially where session state matters, such as browsers with existing cookies, profiles, password managers, and extensions.
- Nexus should **avoid depending on native macOS Spaces** for its primary model, because those are limited and fragile for this kind of workflow.
- Nexus should **own a virtual workspace model** inside one macOS Space per display.
- Nexus should support a **scrolling-strip interaction model** inspired by niri, Rift, Paneru, and ChainYourMac, but applied only to apps opted into the Nexus stage.
- Nexus should start with a **public-API-first core** and isolate any future private-API experimentation behind a clearly separate backend.

The right product framing is:

> **Nexus is a project shell and spatial compositor that orchestrates real macOS windows into a persistent, scrollable, workspace-based environment.**

This is a meaningful product distinction from existing macOS tools:

- Traditional tiling managers manage windows across the whole system.
- Workspace managers generally group or hide applications, but do not own a richer project shell.
- Nexus should do both: **workspace identity + strip layout + selective app orchestration + state-aware adapters**.

That is the opportunity.

---

## 2. Product vision

### 2.1 What Nexus is trying to solve

The current desktop workflow is fragmented:

- macOS Spaces are conceptually useful but operationally brittle.
- Traditional tiling managers are often global, invasive, and fragile.
- Apps each maintain their own tabs, windows, and hidden state.
- Project context is split across editor windows, terminals, browser sessions, and agent tools.
- Switching context becomes “where was that app / tab / desktop / window?” instead of “go to project X”.

Nexus should replace that fragmentation with a single model:

- a **project-aware shell**
- with **virtual workspaces**
- and a **scrollable strip of app slots**
- that reuses the user’s real tools
- while giving the user one place to think about work.

### 2.2 The user experience to optimize for

The ideal experience is:

- The user opens Nexus and stays “inside” it conceptually for the whole day.
- The user no longer thinks in terms of macOS Spaces, random app windows, or hidden tabs.
- Each project/workspace has a stable identity.
- Within a workspace, the user scrolls horizontally across app slots.
- Switching to a different workspace is a vertical move.
- The active slot is centered and legible.
- Real apps are still real apps; Nexus simply arranges, restores, hides, shows, and coordinates them.
- For heavyweight apps, Nexus can use adapters and companion integrations to restore project-specific state instead of keeping too many live windows open.

### 2.3 The key product insight

The insight is not “embed apps”.

The insight is:

> **Create a user-owned spatial model in which real apps are staged, ordered, grouped, and restored as part of a project shell.**

This distinction matters because it keeps the architecture realistic.

---

## 3. Product boundaries and non-goals

These boundaries are intentional and should remain explicit in every phase of development.

### 3.1 Non-goals for v1

Nexus v1 should **not** attempt to:

- truly embed arbitrary third-party native windows as child views inside its own view hierarchy
- replace the user’s preferred browser with an internal WebKit clone
- replace the user’s preferred editor with Monaco or another custom editor
- become a full global tiling window manager for the entire operating system
- deeply automate macOS Spaces as the primary workspace abstraction
- solve every application-specific edge case in the first release
- optimize for App Store compatibility

### 3.2 What Nexus should do instead

Nexus should:

- orchestrate real app windows
- own the workspace graph
- own the strip layout
- own visibility policies
- provide adapters where higher-fidelity state restore is worth it
- keep the browser/editor/terminal story asymmetric instead of forcing one universal abstraction

### 3.3 Distribution assumption

The product is expected to be distributed **outside the Mac App Store**. That simplifies the product strategy, though not the permission model. Accessibility permissions, automation permissions, and possibly Screen Recording permissions will still matter.

---

## 4. Core design principles

These principles should guide architecture and implementation decisions.

### 4.1 Real tools first

Nexus should prefer reuse of the user’s existing apps over internal replacements unless an owned surface creates obvious leverage.

### 4.2 Public API first

The core product should work with public macOS APIs first. If private APIs are explored later, they should live behind an experimental backend.

### 4.3 Virtual workspaces over native Spaces

Nexus should emulate its own workspaces inside one macOS Space per display rather than relying on native Spaces for the primary model.

### 4.4 Project-centric, not window-centric

The product’s unit of organization is the workspace/project, not the raw window.

### 4.5 Stable shell, flexible adapters

The shell architecture should be stable even if specific app integrations change.

### 4.6 Selective orchestration

Nexus should manage only the apps and windows the user explicitly opts into the stage.

### 4.7 Non-disruptive behavior

When the user temporarily opens an unmanaged app, Nexus should not collapse or glitch. Unmanaged apps should be allowed to exist “on top” temporarily without breaking the session.

### 4.8 Agent-friendly system design

The architecture, documents, and task boundaries should be written so coding agents can work on them safely in parallel.

---

## 5. UX concept and interaction model

### 5.1 Workspace geometry

The workspace model should be:

- **Horizontal axis**: app strip / slots within the current workspace
- **Vertical axis**: workspaces
- **Per-display independence**: each display can maintain its own active workspace and strip context

This follows the conceptual strengths of niri while adapting them to macOS and to a project shell rather than a compositor.

### 5.2 Slot model

Each workspace contains an ordered set of slots. A slot may represent:

- one app window
- a grouped stack of windows
- a persistent tool surface
- a floating utility pinned to the workspace
- a slot that is logically occupied but currently cold or rebound

Slots are not just windows. They are **persistent Nexus-owned positions in the workspace model**.

### 5.3 Centering behavior

A focused slot should generally become centered in the active viewport. This is one of the most important UX decisions because infinite horizontal strips become disorienting if the system does not communicate where the user is.

### 5.4 Navigation

Primary navigation modes:

- keyboard navigation left/right across slots
- keyboard navigation up/down across workspaces
- optional trackpad or gesture support
- workspace switcher / overview mode
- direct jump to slot or workspace by shortcut

The first version should prioritize deterministic navigation over purely continuous gesture-driven behavior.

### 5.5 Chrome model

Nexus should provide visible shell UI, but it should not cover the whole screen with one giant interactive layer unless needed.

The safer v1 approach is:

- edge chrome panels
- optional sidebars
- a top HUD or compact status layer
- a lightweight overview mode
- optional overlay controls when invoked

This is better than relying on a giant transparent “hole” window as the only shell primitive.

---

## 6. System architecture overview

Nexus v1 should be built as six primary subsystems:

1. **Stage Chrome**
2. **Window Registry**
3. **Workspace Engine**
4. **Layout Engine**
5. **Visibility Engine**
6. **Adapter Bus**

Supporting subsystems:

7. **Persistence and Config**
8. **Focus/Input Coordination**
9. **Safety and Recovery**
10. **Observability and Diagnostics**
11. **Agent/Automation Interface**

Each subsystem should have a clear contract.

---

## 7. Stage Chrome

### 7.1 Purpose

The Stage Chrome is the user-facing shell layer. It provides:

- workspace navigation UI
- slot indicators
- workspace labels and status
- command palette
- overview mode
- progress/diagnostic surfaces
- optional edge controls for rearranging slots or invoking actions

### 7.2 Recommended implementation shape

Use a combination of:

- a primary Nexus controller window
- one or more HUD/panel windows
- optional edge-aligned panels
- lightweight overlay modes

Avoid a monolithic transparent frame unless later testing proves it is clearly superior.

For the current edge-sliver strip, the practical implementation is: keep the existing controller shell for sidebar, topbar, headers, and indicator, then add passive AppKit mask windows only over the staged app lane. This lets Nexus hide most of the neighboring windows without turning the full shell into one giant click-through hole.

### 7.3 Responsibilities

The Stage Chrome should:

- render the Nexus model
- invoke navigation and orchestration actions
- present state and health information
- remain decoupled from raw AX logic

It should not directly manage low-level window choreography.

### 7.4 Input strategy

The chrome should capture only the interactions that belong to Nexus. The default interaction model should allow the user to work directly in the underlying app windows.

Recommended model for v1:

- keyboard shortcuts drive most navigation
- mouse interaction in app windows remains normal
- trackpad gestures for strip/workspace navigation are optional and feature-flagged
- overview mode becomes the main discoverability surface

---

## 8. Window Registry

### 8.1 Purpose

The Window Registry is the source of truth for discovering, tracking, and resolving real app windows in the user session.

### 8.2 Responsibilities

The registry should:

- discover running applications and their windows
- associate windows with bundle IDs, process IDs, titles, and AX metadata
- observe changes to windows and applications
- expose a stable query layer to the rest of Nexus
- rematch logical Nexus slots to new windows after relaunch or recreation

### 8.3 Public API sources

The registry should rely primarily on:

- Accessibility APIs (`AXUIElement` and attributes such as windows, position, size, title, focused window, minimized state)
- Quartz Window Services (`CGWindowListCopyWindowInfo`) for metadata and screen-layer context
- NSWorkspace / NSRunningApplication notifications for app lifecycle events

### 8.4 Identity model

Do **not** treat raw window IDs as the main durable identity.

Instead, use layered identity:

- **Nexus Slot ID**: the stable logical identity
- **App Identity**: bundle ID + process identity + launch timestamp if needed
- **Window Candidate Metadata**: title, document path, URL, role, subrole, geometry, display
- **Adapter Identity**: app-specific data such as workspace path, profile, session ID, or terminal tag

The registry should expose confidence-scored rematching when windows disappear and reappear.

### 8.5 Why this matters

A slot is persistent even when the actual window changes. This is the difference between a robust workspace model and a fragile “bind slot to current window number” approach.

---

## 9. Workspace Engine

### 9.1 Purpose

The Workspace Engine owns the actual Nexus mental model: projects, workspaces, membership, policies, floating tools, assignment rules, and activation behavior.

### 9.2 Responsibilities

The Workspace Engine should manage:

- workspace CRUD
- slot membership
- active workspace per display
- workspace policies
- floating apps
- display assignment
- hot/warm/cold residency
- app assignment rules
- saved workspace snapshots
- profile switching
- recents/history

### 9.3 Workspaces vs. sessions

A workspace is not only current geometry. It is a durable record of:

- what belongs here
- how it should appear
- how it should be restored
- how it should behave when activated

A workspace may have:

- live state
- saved state
- adapter state
- layout state
- runtime state
- historical state

### 9.4 Assignment model

Assignment rules should support:

- bundle ID
- path patterns
- URL patterns
- title patterns
- adapter-provided metadata
- display preference
- workspace preference
- floating designation
- pinning

### 9.5 Floating apps

Floating apps are apps or windows that should remain visible across workspaces. Examples:

- music
- chat
- calendar
- quick capture
- a pinned monitor panel

This should be a first-class concept early, not an afterthought.

---

## 10. Layout Engine

### 10.1 Purpose

The Layout Engine computes where slots belong on screen.

It does not discover windows and does not directly call app adapters. It translates workspace state into layout positions and visibility instructions.

### 10.2 Layout primitives

The engine should support at minimum:

- **Strip layout**: ordered horizontal slots
- **Centered active slot**
- **Column width presets**
- **Grouped stacks**
- **Per-slot sizing policies**
- **Edge peeking/sliver behavior for offstage windows**
- **Overview layout**
- **Optional compact mode for laptop screens**

### 10.3 Slot types

Recommended slot types:

- `single`
- `stacked`
- `tabbed-group` (future)
- `owned-surface`
- `external-window`
- `hybrid-slot` (stateful adapter that may reuse windows)

### 10.4 Sizing policies

Support layout policies such as:

- fixed width
- fraction of stage width
- min/max width
- content-preferred width
- centered full-width
- secondary/support slot sizing

### 10.5 Viewport model

The stage viewport is conceptual. The engine should compute:

- active slot index
- scroll anchor
- leading and trailing virtual padding for centered end slots
- visible neighborhood
- parked neighborhood
- offstage neighborhood
- revealed fragments for the active slot and edge peeks
- occlusion bands for shell-owned masks

### 10.6 Initial v1 layout scope

For MVP, prioritize:

- one main strip
- one active centered slot
- optional secondary stacked slot
- predictable transitions

Do not overbuild the layout vocabulary too early.

---

## 11. Visibility Engine

### 11.1 Purpose

The Visibility Engine determines which windows are visible, parked, minimized, or hidden when workspaces and slots change.

### 11.2 Core visibility states

Use three primary states:

- **Visible**: currently staged and interactable
- **Parked**: offstage but still warm and recoverable
- **Hidden/Minimized**: cold or inactive at the application/window level

Optionally add:

- **Detached**: temporarily unmanaged by Nexus
- **Recovering**: being rematched or relaunched

### 11.3 Why a three-state model matters

A binary visible/hidden model is too crude because:

- some apps are cheap to keep warm
- some apps are expensive and should be rebound
- some windows should remain offstage without being fully minimized
- multi-monitor behavior benefits from parked windows instead of indiscriminate app-level hide

### 11.4 Parking model

Do not move windows arbitrarily fully offscreen.

Because macOS may relocate fully offscreen windows, the engine should support:

- monitor-aware parking zones
- configurable edge slivers
- safe bounds relative to the current display topology
- a “do not park, minimize instead” rule for problematic apps

The first working edge-sliver slice keeps the active slot and the immediate previous or next neighbor windows fully staged, then hides most of the neighbors behind Nexus-owned mask bands. Farther slots still use the normal parked behavior.

### 11.5 App-level hide vs window-level minimize

The engine should be able to choose among:

- keep visible
- move/resize into stage
- park offstage
- minimize window
- hide application
- relaunch or rebind via adapter

Which strategy is appropriate depends on the app class and workspace policy.

---

## 12. Focus and input coordination

### 12.1 Purpose

This subsystem manages the transition between Nexus-level interactions and the focused real app window.

### 12.2 Key responsibilities

- determine active display, workspace, and slot
- hand focus to the correct target window
- interpret keyboard navigation commands
- optionally support focus-follows-pointer or focus-detection integration
- keep Nexus UI responsive without stealing focus unnecessarily

### 12.3 Initial v1 recommendation

For v1:

- keep input behavior conservative
- use explicit hotkeys for slot/workspace navigation
- avoid over-aggressive gesture interception
- support click-to-focus on staged windows normally
- keep focus synchronization deterministic

### 12.4 Focus recovery

When an app steals focus unexpectedly or the user `cmd+tab`s into a managed window, Nexus should be able to infer the corresponding workspace and optionally activate it.

This should be a configurable behavior.

---

## 13. Adapter Bus

### 13.1 Purpose

The Adapter Bus provides app-specific integration where generic AX/window management is not enough.

### 13.2 Why adapters matter

Different app categories need different treatment:

- browsers already hold valuable session state and should remain mostly external
- editors benefit from workspace-aware state restore
- terminals may be either external or Nexus-owned
- orchestration tools may benefit from direct APIs or agent-friendly bridges

A single generic abstraction is not sufficient.

### 13.3 Adapter types

Support multiple transport types:

- **AX-only adapter**
- **CLI adapter**
- **URL scheme adapter**
- **AppleScript / Apple events adapter**
- **Shortcuts / App Intents adapter**
- **local socket / localhost HTTP adapter**
- **companion extension adapter**
- **owned surface adapter**

### 13.4 Generic adapter contract

Each adapter should optionally implement:

- discover
- activate
- stage
- park
- suspend
- restore-state
- capture-state
- open-target
- health-check
- relaunch
- label
- identify-window
- match-slot
- serialize-state

### 13.5 Adapter health

Every adapter should expose a health state:

- healthy
- degraded
- unavailable
- recovering
- disabled

This is important for diagnostics and for agent-generated tasks.

---

## 14. App strategy by category

### 14.1 Editors (VS Code first)

VS Code is the highest-priority deep adapter because:

- it is heavy enough that naive multi-window duplication can become expensive
- it has strong CLI support
- it has extension APIs
- it has durable workspace/folder concepts

### Recommended strategy

Use a hybrid policy:

- **Hot mode**: keep dedicated windows resident for active/adjacent workspaces
- **Warm mode**: keep a hidden/parked window alive
- **Cold mode**: reuse a VS Code window and restore workspace context

### Companion integration

A VS Code companion extension should be considered early. It can help with:

- saving editor state
- opening the correct folder/workspace
- restoring tabs and file focus
- exposing richer identity than raw window title
- communicating back to Nexus about current repo, workspace file, profile, and mode

### Important boundary

Nexus should not attempt to become a code editor. It should become a stateful orchestrator for the editor.

### 14.2 Browsers

Browsers are the strongest example of why Nexus should reuse real apps.

The default browser strategy should be:

- use the real browser window the user already uses
- preserve existing cookies, profiles, extensions, password-manager integrations
- stage and restore those windows as external windows
- use lighter adapters only where valuable

### Browser adapter scope

Possible browser adapter responsibilities:

- launch specific profile/window targets
- open known URLs for a workspace
- identify or tag workspace-related windows
- optionally expose tab/session metadata where possible
- support picture-in-picture / floating treatment rules
- later support preview or portal features

### Important boundary

Do not assume Nexus can or should fully manage browser internals in v1.

### 14.3 Terminals

Terminals are more flexible.

Nexus can support two modes:

- **External terminal mode**: manage real terminal windows like any other app
- **Owned terminal mode**: use the existing Nexus terminal or a tightly integrated surface

Given the existing Nexus context, this is a good place for owned leverage.

### Terminal recommendation

For v1, support both:

- generic terminal window orchestration
- optional “preferred terminal” adapter
- optional owned terminal surface where it materially improves the experience

cmux is a useful reference because it shows how much leverage a terminal can provide when it is scriptable and stateful without becoming an entire desktop environment.

### 14.4 Agent / orchestration apps

This category is strategically important because these tools often have the richest session semantics and may benefit most from an adapter.

The adapter should capture:

- target workspace/project
- current run/session
- active task/queue
- connection or endpoint state
- tabs or panels where possible
- health or background job status

If you control the orchestration app, add an explicit Nexus bridge early.

### 14.5 Miscellaneous utilities

Utilities such as music players, chat apps, notes, clocks, or scratchpads should usually be treated as:

- floating apps
- pinned apps
- optional overlay surfaces
- low-management entities

---

## 15. Owned surfaces vs external surfaces

Nexus should explicitly distinguish between:

- **Owned surfaces**: UI rendered by Nexus itself
- **External surfaces**: real macOS app windows
- **Hybrid surfaces**: external apps with rich Nexus adapters

### 15.1 Owned surfaces to consider

These are reasonable candidates for owned surfaces:

- command palette
- workspace switcher
- overview grid
- quick notes / scratch capture
- small task/status widgets
- terminal (optional)
- project HUD
- diagnostics panel

### 15.2 External surfaces by default

These should remain external by default:

- browser
- editor
- chat apps
- third-party orchestration tools
- file manager
- media apps

### 15.3 Why this split matters

It keeps Nexus from drifting into “rebuild the operating environment from scratch”.

---

## 16. Persistence and configuration

### 16.1 Purpose

Persistence must capture both durable user intent and short-lived runtime state.

### 16.2 Categories of persisted data

Persist at least:

- workspace definitions
- slot definitions
- assignment rules
- layout preferences
- adapter states
- display mappings
- hotkey configuration
- profile configuration
- recent workspace history
- diagnostics preferences
- feature flags

### 16.3 Suggested persistence layers

Use separate stores for:

- durable config
- runtime state
- volatile caches
- logs and telemetry
- adapter-specific snapshots

### 16.4 Suggested formats

Provide internal structured persistence, but expose configuration export/import through user-readable formats such as:

- JSON
- YAML
- TOML

This is useful for power users, debugging, backup, and agent workflows.

### 16.5 Snapshot model

Workspaces should support snapshots:

- manual snapshot
- on-deactivate snapshot
- periodic snapshot
- adapter-triggered snapshot
- crash-recovery snapshot

---

## 17. Safety and recovery

### 17.1 Why this matters

Any system that moves and hides real user windows must have a strong safety story.

### 17.2 Recovery requirements

Nexus must be able to:

- reveal all managed windows
- disable all parking/hiding behavior immediately
- unload gracefully
- restore windows to sane visible positions
- recover after app crash or forced quit
- identify stale slot bindings
- reattach after app relaunch

### 17.3 Safety mode

Include a **Panic / Reveal All** command from the beginning.

This command should:

- unhide hidden apps if appropriate
- unminimize staged windows where possible
- move parked windows back into safe visible areas
- suspend choreography until the user resumes Nexus control

### 17.4 Watchdogs

Add watchdogs for:

- repeated failed window movements
- repeated failed AX writes
- relaunch loops
- orphaned slot bindings
- offscreen parking failures
- display topology changes

---

## 18. Observability and diagnostics

### 18.1 Purpose

Nexus will be hard to debug without strong observability because many issues will be environmental, app-specific, or permission-related.

### 18.2 Diagnostics that should exist early

Provide a built-in diagnostics surface that shows:

- permissions status
- running managed apps
- visible windows
- slot bindings
- adapter health
- display topology
- active workspace per display
- last orchestration errors
- parking strategy in use
- focus state
- event logs

### 18.3 Logging strategy

Use structured logs with categories:

- registry
- layout
- visibility
- focus
- adapter
- workspace
- display
- recovery
- permissions

These logs should be exportable for debugging and for agent tasks.

---

## 19. Permissions model

### 19.1 Required permissions

Likely required or useful permissions/capabilities include:

- Accessibility permission
- Automation / Apple events permission for scriptable apps
- Screen Recording permission only if preview/portal features are enabled
- Input monitoring only if later gesture/hotkey requirements demand it

### 19.2 Onboarding requirement

The product must include a clear onboarding flow that:

- explains why each permission is needed
- detects whether the permission is granted
- links or guides the user to enable it
- degrades gracefully when it is not granted

### 19.3 Degraded modes

Examples:

- No Accessibility permission → discovery-only or Nexus-owned surfaces only
- No Automation permission → no Apple-event-based adapters
- No Screen Recording permission → no previews or portal captures

---

## 20. Multi-display model

### 20.1 Core principle

Each display should have:

- its own active workspace
- its own strip position / active slot
- its own layout bounds
- its own parking zones

### 20.2 Display assignment modes

Support at least two display assignment strategies:

- **Static**: a workspace belongs to a given display
- **Dynamic**: a workspace can follow or reflect where its staged apps live

### 20.3 Docking and undocking

The system must plan for:

- monitor disconnect
- monitor reconnect
- laptop-only fallback
- topology changes after sleep/wake
- external display reordering

### 20.4 v1 recommendation

For MVP, support:

- single-display reliably
- multi-display as a secondary phase
- a clear “safe fallback to main display” behavior

---

## 21. MVP scope definition

The MVP should prove the product, not the full platform.

### 21.1 The real MVP question

The first useful version is not “everything works”.

The first useful version is:

> **Can a user do real work in one or two project workspaces while Nexus reliably stages editor + terminal + browser and makes switching easier than the default macOS workflow?**

### 21.2 MVP success criteria

The MVP is successful if a user can:

- define at least one real project workspace
- assign at least three apps/windows to it
- navigate across those app slots inside Nexus
- switch to another workspace and back
- have the correct windows appear without confusion
- recover safely if something goes wrong
- use at least one state-aware adapter for a heavyweight app
- rely on the system for repeated daily work

### 21.3 Explicitly out of MVP

The MVP does not need:

- rich portal previews
- deep browser integration
- full multi-monitor parity
- fully continuous gesture physics
- a plugin ecosystem
- dynamic tabbed groups
- native-like animation perfection
- support for every app category

---

## 22. Phase plan

### Phase 0 — Discovery, spikes, and specification freeze

### Goal

Reduce unknowns before implementation.

### Deliverables

- architecture spec
- interaction model spec
- permission map
- candidate app list
- initial data model
- proof-of-concept spike notes
- risk register

### Spike tasks

- AX discovery for windows and focused window
- move/resize/minimize/hide test matrix
- monitor-aware parking experiments
- slot centering math prototype
- simple overlay/HUD prototype
- app identity rematching experiments
- VS Code switching strategy experiments
- browser reuse experiments
- crash/reveal-all recovery experiments

### Exit criteria

- feasibility confirmed on target macOS versions
- no blocker found in AX-based orchestration
- initial set of supported apps chosen
- MVP scope frozen

---

### Phase 1 — Foundation and shell skeleton

### Goal

Build the core project structure and shell without advanced choreography.

### Deliverables

- app shell
- stage chrome skeleton
- permission onboarding
- configuration storage
- logging and diagnostics shell
- basic workspace CRUD
- basic hotkey routing
- internal command bus

### Technical outcome

At the end of this phase, Nexus should know what a workspace is, render its own shell, and store configuration, even if it does not yet perform full window choreography.

### Exit criteria

- workspaces can be created and selected
- app permissions are detectable
- internal state survives relaunch
- diagnostics view exists

---

### Phase 2 — Window registry and single-display strip prototype

### Goal

Make Nexus capable of discovering and staging real app windows on a single display.

### Deliverables

- window registry
- window observation
- single-display layout bounds
- slot-to-window assignment
- strip layout math
- active-slot centering
- visible vs parked logic
- basic focus handoff

### MVP slice

Target exactly three windows to start:

- editor
- terminal
- browser

### Exit criteria

- Nexus can discover candidate windows
- user can assign three windows to one workspace
- user can move left/right between slots
- windows reposition correctly
- offstage windows remain recoverable
- panic/reveal-all works

---

### Phase 3 — Multi-workspace switching and persistence

### Goal

Add vertical workspace switching and durable workspace memory.

### Deliverables

- multiple workspaces
- per-workspace slot definitions
- workspace activation logic
- save/restore of layout positions
- visibility transitions between workspaces
- recent history
- workspace switcher UI
- workspace overview mode

### Exit criteria

- user can switch between at least two workspaces
- each workspace restores its staged windows correctly
- active slot and layout state persist
- switching is faster and clearer than native Spaces for the supported scenario

---

### Phase 4 — Adapter bus and first real integration

### Goal

Add the first app-aware integration, most likely VS Code.

### Deliverables

- adapter bus abstraction
- adapter lifecycle
- generic AX-only adapter
- VS Code adapter
- optional VS Code companion extension
- hot/warm/cold residency policy
- adapter diagnostics
- richer slot identity matching

### Why this phase matters

Without a real adapter, Nexus risks becoming only a clever window mover. This phase turns it into a state-aware shell.

### Exit criteria

- VS Code can participate in workspace switching more intelligently than a generic window
- the user can keep one real project workflow stable across repeated switches
- adapter health is visible and debuggable

---

### Phase 5 — Quality pass for daily use

### Goal

Make the system usable as a daily driver for one real workflow.

### Deliverables

- smoother transitions
- safer parking
- failure recovery improvements
- floating apps
- assignment rules
- display-awareness hardening
- improved keybindings and overview UX
- better onboarding
- better diagnostics and exportable logs

### Exit criteria

- user can work for several days in the same Nexus-managed environment without recurring confusion
- recovery paths are trustworthy
- unassigned apps do not break the experience
- the product feels materially better than ad hoc window management for the chosen workflow

---

### Phase 6 — Multi-display and orchestration workflow support

### Goal

Expand from one stable workspace workflow to a more complete project shell.

### Deliverables

- multi-display activation model
- static/dynamic display assignment
- orchestration tool adapter
- floating utility policy
- profile support
- focus-activation options
- improved slot grouping
- better session snapshots

### Exit criteria

- multi-display behavior is predictable
- the orchestration app participates meaningfully in workspace state
- profiles can represent distinct work modes
- Nexus can handle a more realistic day-to-day session graph

---

## 23. Post-MVP direction

These are important, but should follow the stable shell.

### 23.1 Potential future additions

- ScreenCaptureKit-based live previews / portal panes
- richer browser adapters
- tabbed groups and nested group layouts
- more expressive gesture model
- per-slot AI summaries and health surfaces
- CLI-first automation flows
- config DSL
- private-API experimental backend
- shareable workspace templates
- collaboration or remote-control modes
- richer telemetry and replay tools

### 23.2 Optional private-API backend

If explored later, this backend should be isolated and optional. It may improve:

- tighter window identity mapping
- smoother edge-case behavior
- some choreography performance

It should never be required for baseline product value.

---

## 24. Data model

The following models are intentionally system-design level rather than code-level.

### 24.1 Workspace

```ts
type Workspace = {
  id: string
  name: string
  description?: string
  profileId?: string
  displayPolicy: "static" | "dynamic"
  preferredDisplayId?: string
  activeSlotId?: string
  slotOrder: string[]
  floatingSlotIds: string[]
  layoutState: LayoutState
  visibilityPolicy: VisibilityPolicy
  residencyPolicy: ResidencyPolicy
  assignmentRuleIds: string[]
  adapterStateIds: string[]
  snapshotIds: string[]
  tags: string[]
  createdAt: string
  updatedAt: string
}
```

### 24.2 Slot

```ts
type Slot = {
  id: string
  workspaceId: string
  kind: "single" | "stacked" | "owned-surface" | "external-window" | "hybrid"
  label: string
  appBinding?: AppBinding
  widthPolicy: WidthPolicy
  heightPolicy: HeightPolicy
  layoutRole: "primary" | "secondary" | "support" | "floating"
  adapterId?: string
  adapterStateId?: string
  runtimeBinding?: RuntimeBinding
  lastKnownDisplayId?: string
  pinned: boolean
  warmPreference: "hot" | "warm" | "cold"
  createdAt: string
  updatedAt: string
}
```

### 24.3 AppBinding

```ts
type AppBinding = {
  bundleId: string
  preferredProcessStrategy: "reuse" | "dedicated" | "either"
  titleHints?: string[]
  urlHints?: string[]
  documentHints?: string[]
  profileHint?: string
  launchCommand?: string
  adapterHints?: Record<string, string>
}
```

### 24.4 RuntimeBinding

```ts
type RuntimeBinding = {
  processId?: number
  windowId?: number
  axPath?: string[]
  matchConfidence: number
  state: "attached" | "detached" | "recovering"
  lastSeenAt?: string
}
```

### 24.5 AssignmentRule

```ts
type AssignmentRule = {
  id: string
  name: string
  match: {
    bundleId?: string
    titleRegex?: string
    documentRegex?: string
    urlRegex?: string
    adapterPredicate?: string
  }
  action: {
    workspaceId?: string
    floating?: boolean
    preferredDisplayId?: string
    preferredSlotId?: string
  }
  enabled: boolean
}
```

### 24.6 AdapterState

```ts
type AdapterState = {
  id: string
  adapterId: string
  slotId: string
  health: "healthy" | "degraded" | "unavailable" | "recovering"
  payload: Record<string, unknown>
  capturedAt: string
}
```

### 24.7 LayoutState

```ts
type LayoutState = {
  activeIndex: number
  scrollAnchor: number
  centeredSlotId?: string
  visibleSlotIds: string[]
  parkedSlotIds: string[]
  geometryVersion: number
}
```

### 24.8 VisibilityState

```ts
type VisibilityState = {
  slotId: string
  mode: "visible" | "parked" | "hidden" | "minimized" | "detached"
  strategy: "in-stage" | "edge-sliver" | "safe-zone" | "app-hide" | "window-minimize"
  updatedAt: string
}
```

### 24.9 SessionSnapshot

```ts
type SessionSnapshot = {
  id: string
  workspaceId: string
  reason: "manual" | "deactivate" | "periodic" | "crash-recovery"
  slotStates: Record<string, unknown>
  capturedAt: string
}
```

---

## 25. MVP algorithms and behaviors

### 25.1 Workspace activation algorithm

High-level behavior:

1. Resolve target workspace and display context.
2. Identify current workspace and currently visible/parked windows.
3. Save outgoing workspace runtime snapshot.
4. Compute target layout and slot bindings.
5. For each outgoing slot, apply visibility policy.
6. For each incoming slot, resolve runtime binding:
   - use existing attached window if healthy
   - else try registry rematch
   - else ask adapter to restore/relaunch
7. Apply layout positions to visible slots.
8. Focus target slot.
9. Update chrome and diagnostics.
10. If any slot fails, degrade gracefully and surface the failure.

### 25.2 Left/right slot navigation algorithm

1. Resolve current workspace and active slot.
2. Compute target neighbor according to slot order and grouping rules.
3. Update active slot index.
4. Recompute stage geometry with the new centered slot.
5. Transition visibility states for edge slots if needed.
6. Request focus handoff to the target slot.

### 25.3 Slot matching algorithm

When restoring a slot:

1. Ask adapter for explicit candidate if supported.
2. Query registry for windows of the matching app.
3. Score candidates using:
   - bundle ID match
   - title/document/URL hints
   - previous display
   - geometry proximity
   - last seen time
   - adapter metadata
4. Attach the highest-confidence candidate above threshold.
5. Otherwise, fall back to adapter restore or relaunch.

### 25.4 Parking strategy selection

For each window/app:

- use `edge-sliver` when the app tolerates parking well
- use `minimize` when offstage parking is unstable
- use `app-hide` when the app is workspace-scoped and cheap to hide
- use `adapter-suspend` when an app has smarter state transitions

---

## 26. Agent-oriented delivery plan

Because you plan to work with coding agents, the project should be structured for safe decomposition.

### 26.1 The core documentation set

Keep these documents in the repo from the start:

- `docs/product/nexus-vision.md`
- `docs/architecture/nexus-v1-architecture.md`
- `docs/architecture/subsystems/window-registry.md`
- `docs/architecture/subsystems/workspace-engine.md`
- `docs/architecture/subsystems/layout-engine.md`
- `docs/architecture/subsystems/adapter-bus.md`
- `docs/architecture/subsystems/visibility-engine.md`
- `docs/adapters/vscode-adapter.md`
- `docs/adapters/browser-adapter.md`
- `docs/adapters/terminal-adapter.md`
- `docs/testing/manual-test-matrix.md`
- `docs/testing/permissions-test-matrix.md`
- `docs/adr/` for architecture decisions
- `docs/roadmap/phase-plan.md`

### 26.2 How to assign agent tasks

Agent tasks should be:

- narrow
- testable
- bounded to one subsystem when possible
- accompanied by acceptance criteria
- accompanied by file boundaries
- accompanied by a small amount of context, not the whole world

### Good task example

- “Implement the Window Registry’s discovery and observation layer for single-display environments. Use AX and NSWorkspace notifications. Do not attempt layout or choreography. Expose a typed query interface and structured debug logs.”

### Bad task example

- “Build all of Nexus workspace switching.”

### 26.3 Required developer and agent conventions

Use these conventions from the beginning:

- ADRs for major architecture changes
- typed interfaces for subsystem boundaries
- feature flags for unstable behavior
- clear logging categories
- reproducible test scenarios
- sample config fixtures
- simulator docs for manual QA on real apps
- explicit “unsafe / experimental” markers around private API exploration

### 26.4 Suggested repo layout

```text
Nexus/
  Apps/
    NexusApp/
  Packages/
    StageChrome/
    WindowRegistry/
    WorkspaceEngine/
    LayoutEngine/
    VisibilityEngine/
    AdapterBus/
    Adapters/
      GenericAXAdapter/
      VSCodeAdapter/
      BrowserAdapter/
      TerminalAdapter/
    Diagnostics/
    SharedTypes/
  docs/
  scripts/
  fixtures/
  tests/
```

### 26.5 Suggested phase ticket structure

For each ticket, include:

- objective
- subsystem
- dependencies
- input assumptions
- output contract
- acceptance criteria
- manual test steps
- failure cases
- logging requirements

---

## 27. Testing strategy

### 27.1 Testing layers

Use four testing layers:

- unit tests for state machines and scoring logic
- integration tests for subsystem boundaries
- manual real-app matrix testing
- endurance / stability testing

### 27.2 Manual app matrix

Track at least:

- VS Code
- Safari / Zen / preferred browser
- terminal of choice
- orchestration tool
- Finder
- Slack/Discord or chat app
- music app
- PiP-capable browser scenario

### 27.3 Real scenarios to test

Test scenarios such as:

- switch between two coding workspaces rapidly
- disconnect external monitor during active session
- relaunch VS Code while slot remains bound
- sleep/wake cycle with managed windows
- open unmanaged popup/dialog during active workspace
- `cmd+tab` into a managed window from outside Nexus
- browser PiP while switching workspaces
- kill Nexus and recover all windows

### 27.4 Definition of done for daily-driver quality

A phase is not done because the happy path works once. It is done when:

- recovery is credible
- repeated switching is stable
- permissions issues are understandable
- logs explain failures
- the user can trust the system with real work

---

## 28. Risk register

### 28.1 Major risks

### Risk: macOS offscreen relocation behavior
Mitigation:
- safe parking zones
- edge slivers
- per-app parking policy
- minimize fallback

### Risk: fragile window identity
Mitigation:
- slot-centric model
- confidence-based rematching
- adapter hints
- health diagnostics

### Risk: focus confusion
Mitigation:
- conservative hotkey model
- deterministic active-slot rules
- optional focus-activation only after v1 hardening

### Risk: browser/session friction
Mitigation:
- use real browser windows by default
- keep browser adapters shallow in v1

### Risk: editor memory cost
Mitigation:
- hot/warm/cold residency
- VS Code adapter and companion extension

### Risk: display topology instability
Mitigation:
- single-display-first MVP
- explicit topology watcher
- safe fallback to main display

### Risk: permissions failure
Mitigation:
- onboarding
- diagnostics
- degraded mode support

### Risk: overbuilding
Mitigation:
- phase-gated delivery
- strict MVP scope
- no universal embedding ambition

---

## 29. Recommended first implementation slice

If starting tomorrow, the first buildable slice should be:

### Slice A: prove the shell
- create Nexus shell app
- add workspace CRUD
- add diagnostics panel
- detect permissions
- build command routing

### Slice B: prove window choreography
- discover windows for three target apps
- assign them to one workspace
- stage them in a strip
- switch left/right with keyboard
- support panic/reveal-all

### Slice C: prove workspace switching
- add second workspace
- park outgoing windows
- stage incoming windows
- preserve active slot

### Slice D: prove real state leverage
- implement first VS Code adapter capability
- restore one project more intelligently than a generic window manager can

If those four slices work, the product concept is validated.

---

## 30. Final recommendations

### 30.1 What to build

Build Nexus as:

- a **project shell**
- a **virtual workspace manager**
- a **scrollable strip layout system**
- a **state-aware orchestrator of real windows**
- a **selective, opt-in stage for the apps that matter**

### 30.2 What not to build

Do not build Nexus as:

- a universal native app host
- a browser replacement
- a full editor replacement
- a pure tiling WM clone
- a deep macOS Spaces automation layer

### 30.3 The product thesis

The thesis is that users do not really want more window rules. They want a stable **place** for their work to live.

That is what Nexus should become.

---

## 31. Reference notes and external inspiration

These references should inform implementation decisions and future research:

- **Apple Accessibility APIs** for cross-app window discovery, inspection, and manipulation:
  - kAXWindowsAttribute
  - kAXPositionAttribute
  - kAXMinimizedAttribute
  - AXObserver / AXObserverAddNotification
  - AXUIElement
- **Quartz Window Services** for window metadata:
  - `CGWindowListCopyWindowInfo`
- **AppKit shell primitives**:
  - `NSWindow.StyleMask.nonactivatingPanel`
  - `NSWindow.ignoresMouseEvents`
  - `NSRunningApplication.hide()` / `unhide()`
- **ScreenCaptureKit** for future portal/preview features:
  - `SCShareableContent`
- **AeroSpace** for public-API-first workspace philosophy and private-API isolation
- **FlashSpace** for virtual workspace design, floating apps, profiles, display assignment, and switcher ideas
- **Paneru** for parking constraints and the infinite-strip model
- **Rift** for niri-style scrolling columns on macOS
- **niri** for the conceptual strip/workspace geometry
- **VS Code** for CLI and extension integration points
- **cmux** for the idea of a scriptable terminal/agent surface that complements a workspace shell rather than replacing the whole environment
- **Ghostty tiling WM notes** as a warning about tab/window semantics in terminal integrations

---

## 32. Source links

### Apple documentation
- [kAXWindowsAttribute](https://developer.apple.com/documentation/applicationservices/kaxwindowsattribute)
- [kAXPositionAttribute](https://developer.apple.com/documentation/applicationservices/kaxpositionattribute)
- [kAXMinimizedAttribute](https://developer.apple.com/documentation/applicationservices/kaxminimizedattribute)
- [AXUIElement.h](https://developer.apple.com/documentation/applicationservices/axuielement_h)
- [AXObserverAddNotification](https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification)
- [CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:))
- [NSWindow.StyleMask.nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)
- [NSWindow.ignoresMouseEvents](https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents)
- [NSRunningApplication.hide](https://developer.apple.com/documentation/appkit/nsrunningapplication/hide())
- [ScreenCaptureKit / SCShareableContent](https://developer.apple.com/documentation/screencapturekit/scshareablecontent)
- [App Intents](https://developer.apple.com/documentation/appintents)
- [Mac Automation Scripting Guide](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/AutomatetheUserInterface.html)
- [Apple Events entitlement](https://developer.apple.com/documentation/bundleresources/security-entitlements)

### Project references
- [AeroSpace](https://github.com/nikitabobko/AeroSpace)
- [FlashSpace](https://github.com/wojciech-kulik/FlashSpace)
- [Paneru](https://github.com/karinushka/paneru)
- [Rift](https://github.com/acsandmann/rift)
- [niri](https://github.com/niri-wm/niri)
- [cmux](https://github.com/manaflow-ai/cmux)
- [Ghostty tiling window managers note](https://ghostty.org/docs/help/macos-tiling-wms)
- [VS Code command line](https://code.visualstudio.com/docs/configure/command-line)
- [VS Code built-in commands / vscode.openFolder](https://code.visualstudio.com/api/references/commands)
