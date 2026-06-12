# Firebase Setup (Phase 1 — multi-device sync)

The app runs **local-only** until you complete these steps. The code is already
wired with a *guarded* startup: if Firebase isn't configured, it silently falls
back to the on-device Hive store, so nothing breaks in the meantime.

## 1. Install dependencies

> ⚠️ This machine currently can't run `flutter`/`dart` because the Xcode license
> hasn't been accepted. Run this once first:
>
> ```bash
> sudo xcodebuild -license
> ```

```bash
flutter pub get
```

This fetches `firebase_core`, `firebase_auth`, `cloud_firestore` and clears the
"unresolved package" errors in:
- `lib/services/firebase_bootstrap.dart`
- `lib/services/firebase_auth_service.dart`
- `lib/data/firestore_repository.dart`

At this point the app still runs in **local mode** (no project configured yet).

## 2. Create the Firebase project & wire platforms

```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
firebase login
flutterfire configure            # creates the project link + lib/firebase_options.dart
```

`flutterfire configure` also drops the native config files
(`android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`).

Then enable the products in the Firebase console:
- **Authentication → Sign-in method → Anonymous → Enable** (Phase 1 guest mode)
- **Firestore Database → Create database**

## 3. Activate the generated options

In `lib/services/firebase_bootstrap.dart`:
- uncomment `import '../firebase_options.dart';`
- pass `options: DefaultFirebaseOptions.currentPlatform` to `Firebase.initializeApp(...)`.

On next launch `FirebaseBootstrap.start()` will initialize Firebase, sign in a
guest (anonymous) user, and select the `FirestoreRepository`.

## 4. Deploy & test the security rules

```bash
firebase deploy --only firestore:rules        # deploys firestore.rules
```

Before trusting them, exercise the **member-only** rules against the emulator:

```bash
firebase emulators:start --only firestore
```

Rules to verify (`firestore.rules`):
- a user can read/write a group only if their uid is in `memberIds`
- expenses gated by `visibleTo`; settlements gated by group membership
- a non-member is denied

## Still TODO (not in Phase 1)

- **Migrate screens** from `HiveService` + `ValueListenableBuilder` to
  `Services.repository` + `StreamBuilder`. Until then, configuring Firebase
  alone won't move the UI onto the cloud — the data layer is ready, the screens
  aren't switched over yet.
- **Personal-expense ownership** in multi-user (currently `payerId/groupId =
  'personal'`; needs a real owner uid).
- **Guest → account linking** and contact/QR invites (Phase 2).
- **Move the Gemini API key** out of the client into a Cloud Function.
