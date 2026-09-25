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

### TV Beta & Profile Mode (Production)

> [!IMPORTANT]
> All TV Beta verification must be executed using the `prod` flavor and the `--profile` flag. This ensures the application connects to production endpoints with Ahead-Of-Time (AOT) compilation while maintaining diagnostic performance telemetry on target TV hardware.

#### 1. Run Beta Build on Connected TV / Emulator
```bash
flutter run --flavor prod -t lib/main_prod.dart --profile
```

#### 2. Clean Install for Fresh Beta Verification
Use this procedure when testing fresh database synchronization or clean companion pairing:
```bash
flutter clean && flutter pub get
flutter run --flavor prod -t lib/main_prod.dart --profile --uninstall-first
```

#### 3. Compile Standalone Profile APK for Sideload Testing
To generate a distributable profile-mode APK for beta testers:
```bash
flutter build apk --flavor prod -t lib/main_prod.dart --profile
```
*Output path: `build/app/outputs/flutter-apk/app-prod-profile.apk`*

> [!NOTE]
> Using `flutter run` without flags defaults to `main.dart` and `.env`. Always supply `--flavor prod -t lib/main_prod.dart` to maintain strict environment separation.

