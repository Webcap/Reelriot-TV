# caffeine_tv

Android TV Flutter app for Caffeine (movies and TV; auth via pairing code).

## Configuration

Copy `.env.example` to `.env` and set:

- `CAFFEINE_API_URL` – API base URL. **When running the app on the Android TV emulator**, the device cannot use `localhost`. Point this to your host machine instead:
  - **Emulator**: `http://10.0.2.2:3000` (replace `3000` with your API port). Ensure caffeine-api is running on your machine and listening on `0.0.0.0` or the same port.
  - **Production**: e.g. `https://caffeine.synqholdings.com/`
- `SUPABASE_URL`, `SUPABASE_ANON_KEY` (or `SUPABASE_ANNON_KEY`) – from your Supabase project.
- `TMDB_API_KEY` – for metadata.
- `PAIRING_PAGE_URL` (optional) – URL of the web page where users enter the TV code (e.g. caffeine-admin tv-pair page).

If the pairing screen shows **"Could not get code"**, check: (1) API is running and reachable, (2) `CAFFEINE_API_URL` from the emulator: use `http://10.0.2.2:PORT` for local API.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
