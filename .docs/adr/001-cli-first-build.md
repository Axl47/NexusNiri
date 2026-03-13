# ADR 001: CLI-first native build workflow

## Status

Accepted on 2026-03-12.

## Context

Nexus needs to remain a native macOS app, but the preferred day-to-day workflow avoids opening Xcode just to build and run the app.

## Decision

The repository uses a root Swift package and terminal scripts as the primary development workflow. `swift build` produces the executable, and checked-in scripts bundle the executable into `build/Nexus.app` using `AppResources/Info.plist` and `AppResources/Nexus.entitlements`.

## Consequences

- Contributors can build, test, and run the app from the terminal.
- The repository does not carry a hand-maintained `.xcodeproj`.
- Release packaging may still use Apple CLI tools and may later fall back to `xcodebuild` if necessary, but that is not the default path.
