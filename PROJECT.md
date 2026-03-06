# PROJECT.md — Trucoshi App (Flutter)

This file captures project context so a new contributor (or fresh AI session) can quickly continue work.

## What this is

`trucoshi-app` is the new **Flutter** client for Trucoshi:

- Android + iOS first
- Web later (same codebase)

Backend target is the Rust monorepo `github.com/jfrader/trucoshi-rs`.

## Core constraints / goals

- Mobile-first UI.
- The game supports **1v1 / 2v2 / 3v3** (2/4/6 seats). The table layout must adapt well to small screens.
- Seating should be rendered so **the local player is always at the bottom** (rotate seat indices by `me.seatIdx`).
- Prefer using **Flame** for the game/table rendering loop *when it actually helps* (e.g. animations, card movements), while keeping normal Flutter widgets for screens/forms.
- Reuse the existing **card image assets** from `trucoshi-client`.

## Protocol / backend contract

- Realtime uses **WebSocket protocol v2** from `trucoshi-rs`.
- `/v2/ws` supports **guest mode** (no auth header) for quick "open the app and see it" workflows.
- Authenticated mode uses: `Authorization: Bearer <access_token>`.
- JSON schemas + generated TS types live at: `trucoshi-rs/schemas/ws/v2/`.

## Immediate milestones

- Minimal app structure + configuration for API base URL.
- Auth/login flow placeholder (enough to obtain an access token).
- WS v2 client layer (connect/reconnect, envelope encode/decode, correlation ids).
- Table screen skeleton (seats + center trick area + hand/action bar + chat/commands bottom sheet).
- Dev environment: run backend + web preview together via Docker Compose.
