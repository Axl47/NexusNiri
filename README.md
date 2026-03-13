# NexusNiri

CLI-first native macOS shell prototype for spatial workspaces.

## Development

From the repository root:

```bash
export NEXUS_CODESIGN_IDENTITY="Nexus Dev Local"
# optional override; defaults to ~/Applications/Nexus.app
# export NEXUS_DEV_INSTALL_PATH="$HOME/Applications/Nexus.app"

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

Diagnostics now includes runtime build identity (signing mode, identity label, launch path match) and clearly reports when generic window choreography is blocked because Accessibility is denied.

The current shell is focus-driven: use the sidebar, slot headers, topbar arrows, or keyboard shortcuts to move between workspaces and slots. The stage viewport is no longer a horizontally draggable `ScrollView`, and stage-level resize handles are intentionally deferred while the v1 strip model settles.
