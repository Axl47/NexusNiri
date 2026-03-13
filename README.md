# NexusNiri

CLI-first native macOS shell prototype for spatial workspaces.

## Development

From the repository root:

```bash
rtk proxy bash ./scripts/dev-build.sh
rtk swift test
rtk proxy bash ./scripts/dev-run.sh
```

The app is bundled into `build/Nexus.app` so permissions, bundle identity, and window behavior match a real macOS app more closely than a raw SwiftPM executable.
