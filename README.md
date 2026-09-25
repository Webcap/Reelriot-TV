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

## Build & Version Management

This section provides technical instructions for managing application versions and build numbers in accordance with the IEC/IEEE 82079-1 standard.

### 1. Purpose and Scope
The [`tools/build_number_gen.dart`](file:///c:/Users/cnieves.wmg/Desktop/Projects/Reelriot-TV/tools/build_number_gen.dart) utility provides automated, atomic version management for ReelRiot TV by modifying the `version:` descriptor in [`pubspec.yaml`](file:///c:/Users/cnieves.wmg/Desktop/Projects/Reelriot-TV/pubspec.yaml). It supports Semantic Versioning (SemVer), Calendar Versioning (CalVer: `YYYY.MM.DD`), Git commit-count sequencing, and timestamp-based sequencing.

### 2. Prerequisites & Operational Requirements
- **Dart SDK:** `^3.11.1` (included with Flutter).
- **Working Directory:** Command must be executed from the project root directory containing [`pubspec.yaml`](file:///c:/Users/cnieves.wmg/Desktop/Projects/Reelriot-TV/pubspec.yaml).
- **Git CLI:** Must be installed and reachable in `PATH` if using `--git` commit-count sequencing.

### 3. Command Syntax & CLI Reference

```bash
dart run tools/build_number_gen.dart [options]
```

| Parameter / Flag | Argument | Description | Default Behavior |
| :--- | :--- | :--- | :--- |
| *(None)* | — | Increments the integer build number by `+1` while preserving the existing version name. | `1.0.0+2` → `1.0.0+3` |
| `--dry-run` | — | Simulates version changes and prints planned output to stdout without modifying `pubspec.yaml`. | Disabled (writes to disk) |
| `--sync` | — | Reads and outputs the current version string from `pubspec.yaml` without making changes. | Writes new version |
| `--calver` | — | Formats the version name to today's date (`YYYY.MM.DD`) and increments the build number by `+1`. | Preserves current version name |
| `--version`, `-v` | `<val>` | Sets an explicit version name string (e.g., `1.0.1` or `2026.09.25`). | Current version name |
| `--build`, `-b` | `<num>` | Sets an explicit build number integer (e.g., `15`). | Current build number `+1` |
| `--git` | — | Sets the build number to the current total Git commit count (`git rev-list --count HEAD`). | Incremental `+1` |
| `--timestamp` | — | Sets the build number to the current timestamp (`YMMddHHmm`). | Incremental `+1` |
| `--help`, `-h` | — | Displays the command line usage and argument manual. | — |

### 4. Step-by-Step Operating Procedures

#### Procedure A: Routine Build Increment
To prepare a new incremental build while retaining the active version name:
1. Ensure the repository working directory is clean or desired changes are staged.
2. Execute the generator without arguments:
   ```bash
   dart run tools/build_number_gen.dart
   ```
3. Verify console output confirms the update:
   ```text
   ========================================
   ReelRiot TV Build Generator
   ========================================
   Previous Version : 1.0.0+2
   New Version      : 1.0.0+3
   Version Name     : 1.0.0
   Build Number     : 3
   Dry Run          : false
   ========================================
   Updated pubspec.yaml -> version: 1.0.0+3
   Success! Build version set to 1.0.0+3
   ```

#### Procedure B: Calendar Versioning (CalVer) Release
To align the version name with the current release date (`YYYY.MM.DD`) and advance the build number:
1. Run the script with the `--calver` option:
   ```bash
   dart run tools/build_number_gen.dart --calver
   ```
2. Verify [`pubspec.yaml`](file:///c:/Users/cnieves.wmg/Desktop/Projects/Reelriot-TV/pubspec.yaml) reflects `YYYY.MM.DD+<incremented_build>`.

#### Procedure C: Dry-Run Pre-Flight Inspection
To preview version calculation without writing to disk:
```bash
dart run tools/build_number_gen.dart --dry-run
```

#### Procedure D: Query Current Version for CI/CD Pipelines
To extract the active version string without side effects:
```bash
dart run tools/build_number_gen.dart --sync
```

### 5. Troubleshooting and Error Handling

| Symptom / Error Message | Root Cause | Corrective Action |
| :--- | :--- | :--- |
| `Error: pubspec.yaml not found. Please run from project root.` | Script was executed from an invalid working directory. | Change directory to the root of `Reelriot-TV` and re-run. |
| `Error: Could not find valid "version:" entry in pubspec.yaml` | The `version:` field in `pubspec.yaml` is missing or malformed. | Verify [`pubspec.yaml`](file:///c:/Users/cnieves.wmg/Desktop/Projects/Reelriot-TV/pubspec.yaml) contains a valid `version: X.Y.Z+N` line. |
| Git commit count falls back to increment | Git is not available in system `PATH` or repo has no commits. | Ensure Git CLI is installed and repository has initialized commit history. |

