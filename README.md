# Expensio

A Flutter app for tracking personal expenses and splitting group bills. Scan receipts with your camera, let AI parse the items, and settle up with the least number of transfers.

---

## Features

**Group Expense Splitting**
- Create groups, add members, and log shared expenses
- Split bills equally or with custom amounts per person
- Smart settlement algorithm — finds the minimum number of transfers to clear all debts
- View per-member balances at a glance

**Bill Scanning**
- Photograph or upload a receipt
- Google ML Kit reads the text; Gemini AI extracts items, quantities, and prices
- Review and edit parsed items before creating an expense

**Personal Expense Tracking**
- Log personal expenses with categories
- 7-day spending bar chart and category breakdown
- Filter transactions by category

**Settings**
- 10 supported currencies (INR, USD, EUR, GBP, JPY, CAD, AUD, SGD, AED, SAR)
- Daily reminders — settlement nudge at 8 PM, expense log prompt at 9 PM
- Export all data as JSON
- Monthly spending history

---

## Tech Stack

| Layer | Choice |
|---|---|
| Framework | Flutter 3 |
| Local storage | Hive |
| OCR | Google ML Kit |
| AI parsing | Google Gemini 2.5 Flash Lite |
| Charts | fl_chart |
| Notifications | flutter_local_notifications |
| Font | Poppins |

---

## Getting Started

**Prerequisites:** Flutter 3.0+, Android SDK / Xcode

```bash
# Install dependencies
flutter pub get

# Run
flutter run
```

**After modifying any Hive model:**
```bash
flutter pub run build_runner build
```

---

## Project Structure

```
lib/
├── main.dart
├── models/          # Hive-annotated data models
├── screens/         # UI screens
├── services/
│   ├── hive_service.dart         # All CRUD operations
│   ├── settlement_service.dart   # Greedy + optimal settlement algorithm
│   ├── gemini_service.dart       # Bill parsing via Gemini API
│   ├── notification_service.dart # Local notification scheduling
│   └── app_settings.dart         # Currency and notification preferences
└── utils/
    └── app_theme.dart            # Dark theme + shared components
```

---

## Settlement Algorithm

For groups with 10 or fewer members, the app uses backtracking to find the provably optimal set of transfers (fewest transactions). For larger groups it falls back to a greedy O(n log n) approach — largest debtor pays largest creditor first.

---

## Notes

- All data is stored locally on device — no account or backend required
- The Gemini API key is hardcoded in `gemini_service.dart`; replace it with your own before sharing the project
- Notification scheduling uses exact daily times; Android 12+ may require the `SCHEDULE_EXACT_ALARM` permission depending on your target
