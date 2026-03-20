# caffeine_tv

Android TV Flutter app for Caffeine (movies and TV; auth via pairing code).

## Configuration (Flavors)

The app uses Flutter Flavors to separate Development and Production environments.

1.  **Production (`prod`)**: Uses `.env.prod`. Point this to your live API.
2.  **Development (`dev`)**: Uses `.env.dev`. Point this to your local API (e.g., `http://10.0.2.2:3000`).

Set the following variables in both `.env.dev` and `.env.prod`:
- `CAFFEINE_API_URL`
- `SUPABASE_URL`, `SUPABASE_ANNON_KEY`
- `TMDB_API_KEY`
- `PAIRING_PAGE_URL`

## Running with Flavors

To run a specific flavor, use the `--flavor` flag and the corresponding target file:

### Development
```bash
flutter run --flavor dev -t lib/main_dev.dart
```

### Production
```bash
flutter run --flavor prod -t lib/main_prod.dart
```

> [!NOTE]
> Using `flutter run` without flags will use the default `main.dart` and `.env`, but it is recommended to use the flavor commands above for consistent environment separation.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
