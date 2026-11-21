#!/usr/bin/env bash
# One-time setup for Grub. Run from the project root:  bash scripts/setup.sh
set -euo pipefail

echo "▶ Generating Android / iOS / web platform folders (keeps lib/ untouched)…"
flutter create . --org com.akoel --project-name grub --platforms=android,ios,web

echo "▶ Raising Android minSdk to 23 (required by Firebase Auth)…"
GRADLE=android/app/build.gradle.kts
[ -f "$GRADLE" ] || GRADLE=android/app/build.gradle
sed -i.bak -E 's/minSdk *= *flutter.minSdkVersion/minSdk = 23/; s/minSdkVersion +flutter.minSdkVersion/minSdkVersion 23/' "$GRADLE" && rm -f "$GRADLE.bak"

echo "▶ iOS deployment target 13.0 (Firebase)…"
if [ -f ios/Podfile ]; then
  sed -i.bak -E "s/^# platform :ios, '[0-9.]+'/platform :ios, '13.0'/" ios/Podfile && rm -f ios/Podfile.bak
fi

echo "▶ Installing packages…"
flutter pub get

echo "▶ App icon and splash screen from the Grub logo…"
dart run flutter_launcher_icons
dart run flutter_native_splash:create

echo "▶ Running calculation tests…"
flutter test

cat <<'MSG'

✅ Grub is ready to run in DEMO MODE (data on the device, demo prices):
     flutter run

To connect Firebase (accounts, cloud sync, AI, admin):
  1. npm i -g firebase-tools && dart pub global activate flutterfire_cli
  2. firebase login
  3. flutterfire configure --project=<your-project-id> --platforms=android,ios,web
  4. firebase deploy --only firestore,storage
  5. cd functions && npm install && firebase functions:secrets:set GEMINI_API_KEY && firebase deploy --only functions
  6. Seed the catalogue: see README.md → "Seed the database"
MSG
