# Grub – Plan meals. Shop smarter.

A Kenyan grocery-planning and budgeting app for **Android and iOS** (Flutter), with a **Firebase** backend, an **AI meal assistant** and a **web admin dashboard**.

Flow inspired by the reference video: *Get started → where do you shop → who's eating → which meals → which days → how you eat → cooking vibe → allergies → dislikes → what you already have → weekly budget slider → "building your week" → "Your week is ready!" → grocery list → recipe.*

---

## 1. What's in the box

```
lib/
  main.dart                 Starts Firebase, or falls back to DEMO MODE (works with no setup)
  app.dart                  Splash → welcome/auth → onboarding → main app
  core/                     Theme (Grub colours), Money (integer cents), units, config
  models/                   Product, Recipe, PriceRecord, Supermarket, UserProfile, MealPlan,
                            ShoppingList, PantryItem, Expense
  services/
    calculation_service.dart   ALL grocery maths (scaling, pantry subtraction, packages, totals, budget)
    meal_planner_service.dart  Plan generator + diet/allergy filter + "what can I cook with KSh X"
    optimizer_service.dart     Savings suggestions (cheaper products, meal swaps, cheaper shop, seasonal)
    ai_service.dart            Calls the secure Cloud Function; offline rules-based fallback
    auth_service.dart          Email, Google, password reset (Firebase) / local demo auth
    export_service.dart        Share list as text, export branded PDF
  data/                     Repository: Firestore (production) or on-device (demo)
  state/app_state.dart      Single source of truth – every change recalculates totals
  screens/                  All app screens (see list below)
  admin/                    Admin dashboard (Flutter web)
assets/
  branding/                 Grub logo + app icon
  seed/                     58 products, 27 Kenyan recipes, 6 shops, DEMO prices
functions/                  Cloud Functions (TypeScript): AI proxy, admin roles, price approvals,
                            stats, account deletion + seed / make-admin scripts
firestore.rules, storage.rules, firestore.indexes.json, firebase.json
test/calculation_service_test.dart
```

### Screens
Splash · Welcome · Register · Login · Forgot password · Onboarding (11 steps, incl. household setup & budget) · Home dashboard · Grocery/budget calculator · Building-your-week · Week ready (swap meals) · Weekly meal planner (replace, remove, drag to rearrange, mark cooked) · Recipes / meal selection · Recipe details (servings scaling, cook step-by-step) · Ingredients for the plan (needed / at home / to buy) · "What do I already have?" · Shopping lists · Shopping list details (edit qty & price, tick, share, PDF, finish shopping) · Compare prices (basket per shop + single product) · Find savings · AI assistant · Budget tracking (charts) · Expense history · Pantry inventory (expiry, storage) · Profile · Settings (notifications, privacy, security, sign out, delete account).

Bottom navigation: **Home · Meal Planner · Shopping · Pantry · Profile**.

---

## 2. Run it today (demo mode – no accounts needed)

Requirements: Flutter 3.27+ (`flutter doctor` clean), Android Studio and/or Xcode.

```bash
cd grub
bash scripts/setup.sh      # creates android/ ios/ web/, sets minSdk 23, icons, splash, runs tests
flutter run                # pick your phone or emulator
```

Without Firebase the app runs in **demo mode**: one local account, data saved on the phone, bundled recipes and **demo prices** (clearly labelled in the UI).

---

## 3. Connect Firebase (accounts, sync, AI, admin)

**Recommended: publish from GitHub, like CR Loyalty – follow [GITHUB_FIREBASE_SETUP.md](GITHUB_FIREBASE_SETUP.md).** Pushing to `main` publishes the app to https://grub-kenya-4965c.web.app and the admin to `/admin`; server deploys, seeding and admin roles are buttons under GitHub Actions.

Manual route (from your computer):

### Credentials you need to provide
| What | Where to get it | Where it goes |
|---|---|---|
| Firebase project | console.firebase.google.com → Add project (Blaze plan needed for Functions) | `flutterfire configure` writes `lib/firebase_options.dart`, `google-services.json`, `GoogleService-Info.plist` |
| Gemini API key | aistudio.google.com → Get API key | `firebase functions:secrets:set GEMINI_API_KEY` (server only – never in the app) |
| Service account JSON (for seeding / first admin) | Firebase console → Project settings → Service accounts → Generate key | save as `functions/service-account.json` (git-ignored) |
| SHA-1 / SHA-256 of your Android signing key (Google sign-in) | `cd android && ./gradlew signingReport` | Firebase console → Project settings → Android app |
| iOS URL scheme (Google sign-in) | `REVERSED_CLIENT_ID` in `GoogleService-Info.plist` | Xcode → Runner → Info → URL Types |

### Steps
```bash
npm i -g firebase-tools
dart pub global activate flutterfire_cli
firebase login
flutterfire configure --project=<project-id> --platforms=android,ios,web
firebase use <project-id>
```
In the Firebase console enable **Authentication → Email/Password and Google**, create **Firestore** and **Storage** (location: `africa-south1` Johannesburg is closest to Kenya).

```bash
firebase deploy --only firestore,storage               # rules + indexes
cd functions && npm install
firebase functions:secrets:set GEMINI_API_KEY
firebase deploy --only functions
```

### Seed the database
```bash
cd functions
GOOGLE_APPLICATION_CREDENTIALS=./service-account.json npm run seed
# or without demo prices:  npm run seed -- --skip-prices
```

### Make yourself an admin
Register in the app first, then:
```bash
GOOGLE_APPLICATION_CREDENTIALS=./service-account.json npm run make-admin -- you@example.com
```

### Admin dashboard
```bash
flutter run -d chrome -t lib/admin/main_admin.dart
# published automatically by GitHub Actions at https://grub-kenya-4965c.web.app/admin
```
Products, prices (with brand, package size, shop, location, date, **source** and **status**: verified / user-submitted / estimate / demo), supermarkets, recipes (ingredients, quantities, instructions, nutrition, photo upload), categories, user price reports (approve as verified or user-submitted, or reject), reported content, statistics and admin roles. Protected by the `admin` custom claim in the dashboard **and** in Firestore/Storage rules.

---

## 4. How the maths works (`calculation_service.dart`)
- **Scaling:** required = original × (selected servings ÷ recipe servings). Kids count as half portions.
- **Units:** everything converts to a base unit (g, ml, pcs, bunch, packet); kg/l ×1000, tbsp 15, tsp 5, cup 250.
- **Duplicates:** the same ingredient across recipes becomes one line.
- **Pantry:** to buy = required − at home; zero or less is dropped.
- **Packages:** you buy whole packets – `ceil(quantity ÷ package size) × package price`.
- **Totals / remaining:** sum of lines; remaining = budget − estimate. Money is stored as integer cents (no rounding drift).
- **Planner:** filters allergies/diet/dislikes (hard rules), spreads the budget across meals (breakfast 20 %, lunch 35 %, dinner 40 %, snacks 5 %), then swaps the priciest meals for cheaper ones until it fits.
- **AI:** the model only picks recipe IDs from a list with costs computed from Grub's prices; the app recalculates every shilling it shows.

Run the tests: `flutter test` (Dart) and `cd functions && npm test` (server pricing).

---

## 5. Prices – important
All seeded prices are **demo estimates** (`verificationStatus: "demo"`, source "Demo estimate – not a real shop price") and are labelled in the app. Replace them in the admin dashboard with checked shelf prices, or approve user reports. Only add live supermarket integrations where you have legitimate data access.

---

## 6. Release builds
**Android**
```bash
keytool -genkey -v -keystore android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
# create android/key.properties (storePassword, keyPassword, keyAlias=upload, storeFile=upload-keystore.jks)
# and reference it in android/app/build.gradle(.kts) signingConfigs (see flutter.dev/deployment/android)
flutter build appbundle --release
```
**iOS** (Mac + Apple Developer account)
```bash
cd ios && pod install && cd ..
flutter build ipa --release     # then upload with Xcode Organizer or Transporter
```
Before submitting: privacy policy URL, account-deletion link (in-app delete exists), screenshots, and the Firebase SHA keys for the release signing key.

---

## 7. Notes
- The Flutter project was written without access to the Flutter SDK, so run `flutter analyze` after setup; fix any version-related warnings with `flutter pub upgrade --major-versions`.
- Food photos: upload real photos per recipe in the admin dashboard; until then the app shows a branded colour tile with the dish emoji.
- Supermarket names are used only to label prices; don't use their logos without permission.
