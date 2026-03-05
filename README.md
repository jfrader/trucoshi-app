# Trucoshi App

Flutter client for Trucoshi.

- Targets: **Android + iOS first**, **Web later**.
- Backend: [`jfrader/trucoshi-rs`](https://github.com/jfrader/trucoshi-rs)
- Realtime protocol: **WebSocket v2** (`/v2/ws`, bearer token required)

## Dev quickstart

### 1) Run the backend (dev)

In `trucoshi-rs`:

```bash
docker-compose -f docker-compose.dev.yml up --build
```

Health check:

```bash
curl http://localhost:2992/healthz
```

### 2) Run the app

```bash
flutter pub get
flutter run --dart-define=TRUCOSHI_BACKEND_URL=http://localhost:2992
```

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
