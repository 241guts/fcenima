#!/usr/bin/env sh
# Creates the Android project (needs the Flutter SDK), then applies our own
# manifest, launcher icons and "open with" intent filters on top of it.
# Safe to run again: the android/ folder is rebuilt from scratch each time.
set -e
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
flutter create --platforms=android --org com.cinemax --project-name cinemax_player_app "$TMP/scaffold"

rm -rf android
cp -r "$TMP/scaffold/android" android
cp -r android_overrides/. android/
rm -rf "$TMP"

flutter pub get
echo "Android project ready. Build with: flutter build apk --release"
