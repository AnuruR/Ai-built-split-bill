# SnapSplit

Scan a paper receipt, check the items, assign them to people and see who
owes what. Built for Sri Lankan supermarket receipts (Keells, Cargills…),
currency LKR.

Mobile Application Development – Group 51, University of Ruhuna.

## Tech stack
Flutter (Android) · Google ML Kit text recognition (on-device OCR) ·
image_picker · Supabase (Auth + PostgreSQL with Row Level Security) ·
Riverpod · go_router.

## Setup
1. **Database:** in the Supabase dashboard open *SQL Editor*, paste
   `supabase/schema.sql` and run it.
2. **Auth:** *Authentication → Sign In / Providers → Email*. For development,
   turn **Confirm email** off (Supabase's built-in email is rate-limited).
3. **Keys:** copy `env/dev.example.json` to `env/dev.json` and fill in the
   Project URL and publishable (or anon) key from *Project Settings → API
   Keys*. `env/*.json` is git-ignored.
4. **Run:**
   ```bash
   flutter pub get
   flutter run --dart-define-from-file=env/dev.json
   ```
   In Android Studio: *Run → Edit Configurations → Additional run args*:
   `--dart-define-from-file=env/dev.json`.

## Tests
```bash
flutter test                 # 180 unit + widget tests
flutter test --coverage      # writes coverage/lcov.info
```
Database/RLS tests on a local PostgreSQL: see `supabase/test/README.md`.

## Project structure
```
lib/
  config/      build-time configuration (Supabase URL/key)
  models/      Receipt, ReceiptItem, Person, Category, Assignment, SplitMethod
  services/    pure logic (split_calculator, receipt_parser, category_suggester,
               receipt_filter, receipt_mapper) and data access
               (Supabase + offline repositories, OCR, auth)
  providers/   Riverpod state (draft receipt, people, receipts, sync, router)
  screens/     S01–S06, people, login/signup
  widgets/     reusable UI (dialogs, summary view, sync banner…)
  utils/       money (integer cents) and validators
supabase/      schema.sql (tables, RLS, save_receipt) and SQL tests
test/          mirrors lib/
```

## Key design decisions
- **Money is integer cents** everywhere (`Cents = int`); percentages are
  basis points (100% = 10000). No floating point in any calculation.
- **Rounding:** leftover cents go to the first person, so an item's
  assignments always add up exactly to the item amount. This is checked in
  Dart (`SplitCalculator`) *and* in the database (`save_receipt`).
- **Atomic saves:** `save_receipt()` writes a receipt, its items and its
  assignments in one transaction.
- **Security:** Row Level Security — every table is filtered to
  `auth.uid()`. The publishable key ships in the APK; RLS is what protects
  the data.
- **Offline:** receipts and people are cached per user; receipt
  saves/edits/deletes made offline are queued and synced later.
- **Repository pattern:** screens depend on interfaces, so tests use
  in-memory implementations.

## Known limitations
- First sign-in on a device needs internet; adding/renaming/removing people
  needs internet.
- Receipt photos are stored only on the phone that took them
  (`imagePath` is ready to hold a Supabase Storage key later).
- The offline cache (SharedPreferences) is not encrypted.
- OCR accuracy depends on photo quality; the review screen exists so the
  user can correct it.
