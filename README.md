# Trucoshi App

Flutter client for Trucoshi.

- Targets: **Android + iOS first**, **Web later**.
- Backend: [`jfrader/trucoshi-rs`](https://github.com/jfrader/trucoshi-rs)
- Realtime protocol: **WebSocket v2** (`/v2/ws`, bearer token required)

## Dev quickstart

### Option A: Run Flutter locally (mobile-first)

1) Run the backend (dev) in `trucoshi-rs`:

```bash
docker-compose -f docker-compose.dev.yml up --build
```

2) Run the app:

```bash
flutter pub get
flutter run --dart-define=TRUCOSHI_BACKEND_URL=http://localhost:2992
```

### Option B: Run backend + web preview together (Docker)

This repo includes a compose file that spins up:

- Postgres
- `trucoshi-rs` API (built from a sibling checkout)
- Web preview (Flutter web build served by nginx)

Requirements:

- `docker`
- `docker-compose`
- `trucoshi-rs` checked out next to this repo (so `../trucoshi-rs` exists)

Run:

```bash
docker-compose -f docker-compose.dev.yml up --build
```

- Backend: http://localhost:2992/healthz
- Web preview: http://localhost:8080/

## Auth (current status)

For now the login screen is a **placeholder**: paste an `accessToken` (JWT).

- WS v2 requires: `Authorization: Bearer <accessToken>`
- Web note: browser WebSockets can’t set custom headers; we’ll solve this later.

## Assets

Card images are reused from `trucoshi-client` and live under:

- `assets/cards/default/`
- `assets/cards/gnu/`
- `assets/cards/criollo/`

## Rendering

We include **Flame** as an optional tool for table/game animations where it helps.

## Project context

See [`PROJECT.md`](./PROJECT.md).

## License

GPLv3 (see `LICENSE`).
