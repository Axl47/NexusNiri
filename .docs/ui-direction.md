# UI direction spec

*A design language for an app that should disappear.*

---

## Design philosophy

This app is a stage, not a performer. Every pixel of chrome exists to make the apps living inside it more legible, more reachable, more organized — and for no other reason. The moment the frame draws attention to itself, it has failed.

This means the aesthetic is not "minimal for the sake of minimal." It is minimal because the content — the user's actual tools — is visually loud, diverse, and opinionated already. VS Code has its own palette. Safari has its own chrome. The terminal has its own density. The orchestrator has its own information hierarchy. The frame needs to unify these without competing.

The word for this is **recessive design**. The UI should feel like the negative space in a photograph — structuring everything without being the subject.

---

## Color

### The frame palette

The chrome operates in a single-channel palette: white-on-dark with opacity as the only variable. No hue in the frame itself except for a single accent color used sparingly for active state indication.

| Token | Value | Usage |
|---|---|---|
| `--chrome-bg` | `rgba(28, 28, 30, 0.82)` | Sidebar, topbar background |
| `--surface` | `rgba(255, 255, 255, 0.04)` | Resting interactive surfaces |
| `--surface-hover` | `rgba(255, 255, 255, 0.08)` | Hovered interactive surfaces |
| `--text-primary` | `rgba(255, 255, 255, 0.92)` | Active workspace name, focused slot label |
| `--text-secondary` | `rgba(255, 255, 255, 0.50)` | Inactive labels, app names |
| `--text-tertiary` | `rgba(255, 255, 255, 0.28)` | Metadata, hints, strip position indicator |
| `--border` | `rgba(255, 255, 255, 0.08)` | All structural dividers |
| `--accent` | `hsl(248, 58%, 62%)` | Active workspace indicator, strip thumb |
| `--accent-dim` | `hsla(248, 58%, 62%, 0.20)` | Active workspace background fill |

### Why no light mode (for now)

The apps being orchestrated can be anything — light-themed Safari, dark-themed VS Code, a terminal with a custom palette. A dark, translucent frame provides the most neutral container. Light chrome next to a dark editor creates a harsh seam. Dark chrome next to light content creates a subtle vignette that actually helps focus. If light mode is ever introduced, it should be a separate exercise with its own careful tuning, not a variable swap.

### Why no color beyond one accent

Every embedded app brings its own color story. Adding color to the frame means the frame starts having opinions about what "belongs." A purple sidebar next to VS Code's blue activity bar next to Safari's gray chrome creates visual noise. The monochrome frame with a single muted accent lets every app look like itself.

The accent (`hsl(248, 58%, 62%)`) is a muted, cool purple — chosen because it sits outside the typical palette of developer tools (blue for links, green for success, red for errors, yellow for warnings). It won't collide with status colors from the apps inside.

---

## Typography

### Font

System sans-serif stack. The frame is not the place for typographic personality. It is labeling infrastructure — workspace names, app names, slot counts. These should be readable at small sizes and invisible at a glance. A distinctive display font would fight with every app's own typography.

### Scale

Only three sizes exist in the entire frame UI:

| Size | Weight | Usage |
|---|---|---|
| 12px | 500 | Workspace name in topbar (the largest text in the chrome) |
| 11px | 500 | App names in slot headers |
| 11px | 400 | Metadata (app count, slot position, monospaced paths) |

No size exceeds 12px. No weight exceeds 500. Headings do not exist in this UI — there is nothing to "head." The hierarchy is communicated through opacity, not scale.

### Monospace

`--font-mono` for any path, URL, or technical metadata displayed in the topbar or slot headers. This distinguishes "data about the app" from "UI labels" without adding visual weight.

---

## Spatial structure

### The three zones

The interface has exactly three zones, and each has a clear role:

**1. Sidebar (52px wide, fixed)**
The vertical axis. Workspace switching. This is the only persistent navigation in the app. It contains workspace indicators (numbered, 34×34px hit targets with 8px radius), a spacer, and utility actions (add workspace, settings) at the bottom.

The sidebar has a left-edge accent bar (3px wide, accent color) on the active workspace — this is the strongest visual signal in the entire UI and the only use of the accent color at full opacity. It should be immediately scannable: which workspace am I in?

**2. Topbar (36px tall, spans main area)**
The horizontal context bar. Displays: workspace name, separator, metadata (app count and current slot position), and strip navigation arrows. All of this is secondary information — it confirms where you are, it doesn't ask you to do anything.

**3. Viewport (remaining space)**
The stage itself. No padding, no border, no decoration. The app windows fill this space edge to edge. The only UI element overlapping the viewport is the strip position indicator at the bottom (6px tall, nearly invisible).

### The gap

The gap between app slots in the strip is 2px. Not zero (which would make adjacent apps visually merge), not 4px or more (which would introduce a visible "gutter" aesthetic that makes the frame feel like a grid system). 2px is enough to separate without structuring.

### Chrome total

Sidebar (52px) + slot header (28px per slot) + topbar (36px) + strip indicator (6px) = ~122px of non-app vertical space on any given view. On a 1440px tall display, that's 8.5% overhead. The target is under 10%.

---

## The strip

### Scrolling model

The strip is a horizontal sequence of app slots that extends beyond the viewport. The viewport shows a window into this strip, and scrolling shifts which portion is visible.

When a slot receives focus, the strip smoothly scrolls to **center** that slot in the viewport. This is the key interaction — the user doesn't scroll to find apps, they focus apps and the strip adjusts. The centering animation uses a cubic-bezier ease (`0.25, 0.1, 0.25, 1`) at 400ms — fast enough to feel responsive, slow enough to be trackable.

### Slot sizing

Each app slot has a width defined as a percentage of the viewport. This is set per-app in the workspace configuration. Typical distributions:

- Editor-heavy: editor 55%, terminal 35%, orchestrator 40% (total: 130%, meaning scrolling is needed)
- Balanced: editor 50%, browser 45%, terminal 30%, design tool 40% (total: 165%)
- Monitoring: terminal 50%, dashboard 50%, agent panel 45% (total: 145%)

The total always exceeds 100%. If it didn't, you wouldn't need the strip — you'd just tile. The strip's purpose is that **every app gets the space it needs, and you navigate between them** instead of cramming everything into view simultaneously.

### Focus and dimming

The focused slot renders at full opacity. All other visible slots dim to 50% opacity. This is the primary affordance for "which app am I interacting with right now" — a question that every multi-window setup on macOS currently answers poorly.

The dimming is a CSS transition (300ms ease) and applies to the entire slot including its header. When the user clicks into a dimmed slot, it becomes focused and the previously focused slot dims.

### The strip position indicator

A 6px bar at the bottom of the viewport. Contains a 2px track (6% white opacity) and a thumb (accent color, 60% opacity). The thumb width is proportional to viewport/total-strip ratio. Its position reflects scroll offset.

This is not a scrollbar — the user never drags it. It is purely an orientation aid, equivalent to a scroll position dot on a mobile screen. It answers "how much more is to my left/right?"

---

## Slot headers

Each app slot has a 28px header containing:

- App icon (14×14px, rounded 3px, solid color fill matching the app's identity color)
- App name (11px, secondary text color)

The header background is barely distinguishable from the app content beneath it (`rgba(255, 255, 255, 0.03)`). It exists to label, not to frame. A bottom border (0.5px, standard border color) provides the only separation.

### Why not hide the headers?

In early concepts, the headers were omitted — just raw app windows in slots. But without them, adjacent apps with similar color schemes (two terminals, or a dark browser next to a dark editor) become indistinguishable at the boundary. The 28px header is the minimum information needed to orient. It is also the natural place for future per-slot actions (detach, resize, swap) without adding a context menu.

---

## Workspace indicators

The sidebar uses numbered indicators rather than icons or thumbnails. This is a deliberate choice:

- **Numbers are stable.** Workspace 1 is always workspace 1. A thumbnail would change every time the content changes.
- **Numbers are small.** A 34×34px square with a number inside can communicate identity in a fraction of the space a thumbnail or icon would need.
- **Numbers map to shortcuts.** `Cmd+1`, `Cmd+2`, `Cmd+3` — the visual label matches the keybind exactly.

Below each indicator, a micro-label (8px, tertiary opacity) shows the workspace name truncated to 3-4 characters ("API", "UI", "Ops"). This is the secondary identifier — the number is primary.

The active indicator has:
- A background fill of `accent-dim`
- Text color shifted to a lighter tint of the accent
- A 3px × 16px accent bar on the left edge of the sidebar (extending past the indicator's left boundary by the sidebar padding)

Inactive indicators have no background, secondary text color, and gain a hover state (`surface-hover` background).

---

## Material and backdrop

### Translucency

The sidebar and topbar use `backdrop-filter: blur(20px)` with a semi-transparent background. This is not decorative — it serves a functional purpose: it lets the user perceive that there is content (their app windows) behind the chrome, reinforcing the mental model that the frame is a layer on top of their workspace, not a container around it.

The blur radius is 20px — enough to obscure text and details, but enough to let color and brightness bleed through. The frame subtly shifts tone depending on what's behind it (warm when the editor is showing amber syntax highlighting, cool when the terminal is beneath). This is an organic, living quality that helps the frame feel integrated rather than stamped on.

### Borders

All structural borders are 0.5px and use the standard border token (`rgba(255, 255, 255, 0.08)`). This is thinner than any app's internal borders, which means the frame's structure is always visually subordinate to the content's structure. At 0.5px, the borders are felt more than seen — they exist as spatial dividers, not visual elements.

### No shadows

Shadows imply elevation. Elevation implies the frame is "above" the apps. The correct mental model is that the apps are the foreground and the frame is the background infrastructure. No drop shadows, no box shadows, no glow effects anywhere in the frame.

---

## Motion

### Strip scrolling

Slot transitions when scrolling or changing focus use:

```
transition: transform 0.4s cubic-bezier(0.25, 0.1, 0.25, 1)
```

This is a slightly underdamped ease — it arrives at the target position without overshoot but with a smooth deceleration that feels physical. The 400ms duration is calibrated for the typical scroll distance (one slot width, ~600-800px on a standard display).

### Workspace switching

Switching workspaces is a discrete state change, not a scroll. The strip content is replaced instantly (no cross-fade between workspaces — that would imply a spatial relationship between workspaces that doesn't exist). The sidebar indicator transition is fast (200ms) because it's a small UI element.

The rationale for no cross-fade: workspaces are parallel contexts, not a sequence. Animating between them implies you're "traveling" from one to the other. In reality, you're switching which set of apps is active. Instant swap respects this.

### Dimming transitions

Focus/dim transitions on slots use 300ms ease. This is deliberately slower than the strip scroll (400ms) so that the dimming completes visually before the scroll finishes — the user sees which slot is becoming active before the strip finishes centering it.

### What should not animate

- Workspace content appearing after a switch (instant)
- Sidebar indicator bar position (instant, or max 100ms)
- Border opacity changes (instant)
- Strip indicator thumb (matches strip scroll timing, 400ms)

---

## Interaction affordances

### Scrolling the strip

The strip scrolls via focus changes, not direct scroll gestures. The user focuses a slot (by clicking it, or via a keybind), and the strip centers that slot. Navigation arrows in the topbar provide sequential previous/next movement.

Direct trackpad scrolling in the viewport should pass through to the focused app, not move the strip. This is critical — if the strip hijacks horizontal scroll, every web page, every code editor, every app with horizontal content becomes unusable.

**Strip navigation inputs:**
- Click on a visible slot → focus it, strip centers
- Topbar arrows → sequential next/previous slot
- Keybind (configurable) → sequential next/previous slot
- Keybind (configurable) → jump to slot by number

### Workspace switching

- Sidebar click → switch workspace
- Keybind `Cmd+{n}` → switch to workspace n
- Vertical gesture (configurable, e.g. three-finger vertical swipe) → next/previous workspace

### Pass-through

The viewport area is not an interactive surface belonging to the frame — it belongs to the apps. All mouse events, scroll events, keyboard input within the viewport pass through to the underlying app window. The frame only captures input on its own chrome elements (sidebar, topbar, slot headers, strip indicator).

---

## States and edge cases

### Empty workspace

A workspace with no apps assigned shows a centered message in the viewport area: "No apps in this workspace" in tertiary text, with a subtle prompt to add apps. The strip indicator shows an empty track with no thumb.

### Single-app workspace

When a workspace has exactly one app, the strip is unnecessary — the single app fills the viewport with no scrolling. The strip indicator is hidden. The topbar metadata reads "1 app". The slot header is still shown for consistency.

### App not running

If an app assigned to a workspace isn't currently running, its slot shows a muted placeholder: the app icon centered with a label beneath reading the app name. Clicking the slot should launch the app. The slot background uses `--surface` fill.

### Overflowing strip

When the total strip width exceeds 300% of the viewport (many apps or wide apps), the strip indicator thumb becomes very small. At some threshold, consider collapsing to a dot rather than shrinking the thumb below 12px — a tiny sliver is harder to read than a dot that simply says "you're somewhere in a long strip."

---

## What this spec does not cover

- **The onboarding flow** for adding apps to workspaces
- **The configuration UI** for editing workspace layouts, slot widths, and app assignments
- **Companion extension protocols** for communicating state changes to apps like VS Code
- **Global keybind registration** and conflict resolution with the OS
- **Multi-monitor behavior** and per-display strip management
- **The app's own icon, name, and brand identity**

These are implementation and product design concerns that sit outside the visual language. This document defines how the frame looks and feels once it is running, not how the user configures it.

---

## Summary of principles

1. **Recessive, not minimal.** The frame yields to content, but it is not featureless — every element earns its space.
2. **Monochrome + one accent.** The frame has no opinions about color except for one muted signal.
3. **Opacity is the hierarchy.** Text size is nearly constant. Differentiation comes from alpha values.
4. **The strip centers, the user focuses.** Navigation is declarative (I want this slot) not manipulative (I'm dragging the strip).
5. **Borders whisper, shadows don't speak.** 0.5px lines structure space. Nothing floats above anything else.
6. **The viewport is sacred.** 100% of input within it belongs to the apps. The frame never intercepts.
7. **Workspaces switch, they don't transition.** Parallel contexts, not a sequence.
8. **Every app looks like itself.** The frame adapts to content through translucency, not the other way around.
