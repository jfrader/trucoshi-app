# Trucoshi App

Flutter client for Trucoshi.

- Targets: **Android + iOS first**, **Web later**.
- Backend: [`jfrader/trucoshi-rs`](https://github.com/jfrader/trucoshi-rs)
- Realtime protocol: **WebSocket v2** (`/v2/ws`, bearer token required)

## Dev quickstart

### Option A (recommended): run each repo separately

Backend (in `trucoshi-rs`):

```bash
cd ../trucoshi-rs
docker-compose -f docker-compose.dev.yml up --build
```

Frontend (Flutter, in this repo):

```bash
flutter pub get
flutter run --dart-define=TRUCOSHI_BACKEND_URL=http://localhost:2992
```

### Option B: web preview only (Docker) + backend separately

Run backend separately (same as above), then run the web preview:

```bash
docker-compose -f docker-compose.web.yml up --build
```

- Backend: http://localhost:2992/healthz
- Web preview: http://localhost:8080/

### Option C: run backend + web preview together (single compose)

If you *want* one compose file to run everything (Postgres + API + web preview), use:

```bash
docker-compose -f docker-compose.dev.yml up --build
```

This requires `trucoshi-rs` checked out next to this repo (so `../trucoshi-rs` exists).

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
