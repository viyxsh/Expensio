# Expensio

A Flutter app for tracking personal expenses and splitting group bills. Scan receipts with your camera, let AI parse the items, and settle up with the fewest possible transfers — on mobile or the web.

**🔗 Live demo:** <https://viyxsh.github.io/Expensio/>

---

## Features

**Group Expense Splitting**
- Create groups, add members, and log shared expenses
- Split bills equally or with custom amounts per person
- Smart settlement algorithm — finds the minimum number of transfers to clear all debts
- Per-member balances at a glance, plus your own owed/owing position on each group card

**Accounts & Multi-Device Sync**
- Start instantly as a guest; upgrade to an account later with no data loss
- Sign in with email/password or Google
- Cloud sync across devices via Firebase (Firestore), with offline support
- Runs fully local (Hive) when Firebase isn't configured

**Group Invites**
- Invite by shareable code, QR, deep link (`expensio://join/<code>`), or phone contacts
- Joiners can claim a placeholder member to inherit its history and balances

**Settle Up**
- Two-sided confirmation: the payer marks a payment, the payee confirms it
- Optimised "payments needed" list and recorded-payment history

**Personal & Shared Spending**
- Per-transaction amounts reflect *your* money — the full total when you paid, your share when someone else did, with a settled / you-owe indicator
- Adaptive overview chart: weekdays for the week, weeks for the month, months for the year
- Category donut + tappable summary tiles, filterable by category

**Monthly Unwrapped**
- A Spotify-Wrapped-style recap of the month: total spent, top category persona, biggest splurge, and a shareable summary

**Budgets**
- Set an overall monthly cap plus optional per-category budgets
- Progress bars with on-track / nearing / over states and pace-aware warnings

**Settings**
- Light / Dark / System appearance
- 10 currencies (INR, USD, EUR, GBP, JPY, CAD, AUD, SGD, AED, SAR)
- Daily reminders — settlement nudge at 8 PM, expense-log prompt at 9 PM (mobile)
- Export all data as JSON, monthly spending history

---

## Tech Stack

| Layer | Choice |
|---|---|
| Framework | Flutter 3 (Android, iOS, Web) |
| Local storage | Hive |
| Cloud sync & auth | Firebase (Firestore + Auth, Google sign-in) |
| OCR | Google ML Kit |
| AI parsing | Google Gemini 2.5 Flash Lite |
| Charts | fl_chart |
| Notifications | flutter_local_notifications |
| Font | Poppins |

---

## Getting Started

**Prerequisites:** Flutter 3.0+, and Android SDK / Xcode for mobile.

```bash
# Install dependencies
flutter pub get

# Provide your Gemini API key (read from .env at runtime)
echo "GEMINI_API_KEY=your_key_here" > .env

# Run on a device or browser
flutter run                 # mobile
flutter run -d chrome       # web
```

**After modifying any Hive model:**
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

**Quality checks:**
```bash
flutter analyze
flutter test
```

Cloud sync is optional — without a Firebase project the app falls back to local-only mode. To enable it, run `flutterfire configure` (include the platforms you target) so `lib/firebase_options.dart` is populated. See `SETUP.md`.

---

## Project Structure

```
lib/
├── main.dart                 # Bootstrap: Hive, theme, Firebase (guarded), deep links
├── models/                   # Hive-annotated data models (+ generated adapters)
├── data/
│   ├── repository.dart       # Provider-agnostic data interface
│   ├── hive_repository.dart  # Local-only implementation
│   ├── firestore_repository.dart # Cloud implementation
│   ├── balances.dart         # Pure balance + per-user amount maths
│   └── budget.dart           # Pure budget maths
├── state/
│   └── app_state.dart        # Reactive in-memory view over the repository
├── screens/                  # UI (transactions, groups, settle-up, budget, unwrapped, more, auth/)
├── services/
│   ├── settlement_service.dart   # Greedy + optimal settlement algorithm
│   ├── gemini_service.dart       # Bill parsing via Gemini API
│   ├── auth_service.dart / firebase_auth_service.dart / session_controller.dart
│   ├── notification_service.dart # Local notification scheduling
│   └── app_settings.dart         # Currency, theme, reminders, budgets
└── utils/
    └── app_theme.dart        # Light/Dark theme + shared components

test/                         # Unit tests for money, balances, settlement, budget, unwrapped
```

---

## Settlement Algorithm

For groups with 8 or fewer members, the app uses capped backtracking to find the provably optimal set of transfers (fewest transactions). For larger groups it falls back to a greedy O(n log n) approach — largest debtor pays largest creditor first — and keeps whichever result needs fewer payments.

---

## Notes

- Works offline and local-first; cloud sync activates only when Firebase is configured.
- The Gemini API key is read from `.env` (`GEMINI_API_KEY`) — never commit your key.
- Native-only features (bill scanning, contacts, local notifications, file export) are automatically hidden on web; the web build runs in local mode unless a Firebase **web** app is configured.
- Notification scheduling uses exact daily times; Android 12+ may require the `SCHEDULE_EXACT_ALARM` permission depending on your target.
