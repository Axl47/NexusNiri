# ADR 004: Tether is the first deep adapter

## Status

Accepted on 2026-03-12.

## Context

The first validated workflow centers on editor, browser, and Tether. Tether is in a sibling repository and already exposes a local WebSocket server with orchestration identity and server health surfaces, but it does not yet expose Nexus-specific window-management semantics.

## Decision

Nexus will implement `TetherAdapter` first. The adapter should use Tether's existing local WebSocket surface for health and identity today, and it should reserve a future `nexus.*` method namespace for capture, restore, open-target, and bring-to-front semantics.

## Consequences

- Nexus gets immediate leverage from a strategic app instead of waiting for a perfect adapter API.
- The boundary stays explicit and does not overload unrelated Tether orchestration methods with window-management behavior.
- Completing the full adapter will require small changes in the sibling `../Tether` repo later.
