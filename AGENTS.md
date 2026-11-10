# Repository Guidelines

## Project Structure

Hivefy is a Flutter music app with Android and iOS projects. Application code is under `lib/`: `screens/` contains pages and feature flows, `components/` reusable UI, `services/` audio/network/storage/system integrations, `models/` data types and persistence, `shared/` app-wide state and constants, and `utils/` helpers and theming. Static assets, icons, fonts, and documentation images live in `assets/`; platform configuration is in `android/` and `ios/`. Tests belong in `test/`.

Music catalog integrations are implemented in `lib/services/`. `docs/yt_source.md` is a reference for media sources and ideas, not a description of features necessarily implemented in this app. Preserve the distinction between explicitly downloaded songs and the automatic playback cache. Language selections are shared through the language notifier and should refresh language-dependent recommendations without requiring an app restart.

## Product and Data Behavior

- Preserve available song, artist, album, and playlist metadata throughout search, library, and player flows; handle missing values without inventing details. Prefer higher-quality artwork where it is available.
- Keep search input focus stable while suggestions and history update, and constrain long history text to the available width.
- Queue and player views must handle empty or changing queues and constrained screen sizes safely.
- Downloaded Songs in Library contains explicitly downloaded tracks, not automatically cached tracks, and remains accessible offline. Keep its count and contents in sync with download changes.
- Home and related recommendations should follow the saved language selection. Protect against older asynchronous results replacing results for a newer selection.
- Follow the existing compact card layouts and avoid adding a media-source label to Home card subtitles.

## Build, Test, and Development

- `flutter pub get` resolves packages from `pubspec.yaml`.
- `flutter run` launches the app on a connected device or emulator.
- `flutter run -d <device-id>` targets a particular device; use `flutter devices` to find its ID.
- `flutter analyze` runs the Dart/Flutter static analyzer using `analysis_options.yaml` and `flutter_lints`.
- `flutter test` runs the test suite in `test/`.
- `flutter build apk` builds an Android APK.

The declared Dart SDK range is `>3.10.0 <4.0.0`; use a compatible Flutter SDK.

## Coding Style

Follow standard Dart formatting: two-space indentation, trailing commas for multiline argument lists, and run `dart format` on changed Dart files. Use `lower_snake_case.dart` filenames, `UpperCamelCase` for types, and `lowerCamelCase` for members and variables. Keep UI in screens/components and move reusable application logic into services, models, or utilities. Prefer the existing Riverpod patterns for shared state, and avoid adding dependencies when an existing package or utility covers the need.

## Testing Guidelines

Use `flutter_test` for widget and unit tests. Name test files with a `_test.dart` suffix and group related behavior with descriptive test names. Add or update focused tests for changed behavior, then run `flutter test` and `flutter analyze` before submitting. The current suite is small, so do not assume broad coverage from a passing run.

## Commits and Pull Requests

Use short, imperative commit subjects (for example, `Fix queue restore after restart`) and keep each commit focused. PRs should explain the user-visible change, note relevant implementation details, link an issue when applicable, and include screenshots or a short recording for UI changes. Mention the checks you ran and any platform limitations.

## Configuration and Assets

Keep package declarations and Flutter asset/font registrations in `pubspec.yaml` consistent with files under `assets/`. Launcher icon sources, including the iOS dark and tinted variants, are configured there. Do not commit signing keys, credentials, or local machine configuration. Treat external music-service responses as untrusted input and handle missing or malformed fields in parsing code.
