# NexusNiri

CLI-first native macOS shell prototype for spatial workspaces.

## Development

From the repository root:

```bash
export NEXUS_CODESIGN_IDENTITY="Nexus Dev Local"
# optional override; defaults to ~/Applications/Nexus.app
# export NEXUS_DEV_INSTALL_PATH="$HOME/Applications/Nexus.app"
# optional one-shot reset when TCC has a stale Accessibility entry
# export NEXUS_RESET_ACCESSIBILITY_ON_START=1

rtk proxy bash ./scripts/dev-build.sh
rtk swift test
rtk proxy bash ./scripts/dev-run.sh
```

`dev-build` now signs with `NEXUS_CODESIGN_IDENTITY` by default and installs `Nexus.app` into `~/Applications/Nexus.app` unless `NEXUS_DEV_INSTALL_PATH` is set. `dev-run` launches the installed app path so macOS TCC sees a stable app identity across rebuilds.

`NEXUS_CODESIGN_IDENTITY` must be a real code-signing identity, not just any self-signed certificate name. Verify it appears in:

```bash
rtk proxy security find-identity -v -p codesigning
```

`NEXUS_ALLOW_ADHOC=1` is still supported as an explicit fallback for non-TCC debugging, but ad-hoc builds are expected to produce unstable Accessibility trust behavior.

You do not need a paid Apple Developer account for local Accessibility testing. What matters here is a stable local app identity: the same bundle identifier, a stable install path, and a real local code-signing identity that appears in `security find-identity -v -p codesigning`. That is enough for local TCC trust prompts and persisted Accessibility grants on your own Mac.

If macOS gets stuck with a stale Accessibility reference, clear it explicitly and re-prompt:

```bash
rtk proxy bash ./scripts/dev-reset-accessibility.sh
```

Or do it for one launch only:

```bash
NEXUS_RESET_ACCESSIBILITY_ON_START=1 rtk proxy bash ./scripts/dev-run.sh
```

`tccutil reset` only clears an existing grant; it does not assign a new one. After a reset, Nexus should prompt again through `AXIsProcessTrustedWithOptions`, or you can re-enable it in System Settings.

Diagnostics now includes runtime build identity (signing mode, identity label, launch path match) and clearly reports when generic window choreography is blocked because Accessibility is denied.

## Xcode Workflow

If you want to inspect signing, capabilities, entitlements, or run from Xcode directly:

```bash
rtk proxy bash ./scripts/dev-generate-xcodeproj.sh
open Nexus.xcodeproj
```

`project.yml` is the source of truth for the checked-in Xcode project. Regenerate `Nexus.xcodeproj` after changing targets, schemes, or build settings.

Open the `NexusApp` target in Xcode, set your Team or Signing Certificate, and run the `NexusApp` scheme. The app target includes a post-build install step that mirrors the CLI workflow by copying the signed app to `~/Applications/Nexus.app` by default, writing `dev-build-metadata.json`, and re-signing the installed copy with Xcode's selected identity. Override the install path with `NEXUS_DEV_INSTALL_PATH` if needed.

The current shell is focus-driven: use the sidebar, slot headers, topbar arrows, or keyboard shortcuts to move between workspaces and slots. The stage viewport is no longer a horizontally draggable `ScrollView`, and stage-level resize handles are intentionally deferred while the v1 strip model settles.
