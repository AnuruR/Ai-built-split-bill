# Requirements check (FR-01 – FR-14)

| FR | Requirement | Where | How it was verified |
|----|-------------|-------|---------------------|
| FR-01 | Register / sign in / sign out | `screens/login_screen.dart`, `signup_screen.dart`, `services/auth_service.dart`, router `redirect` | Manual on device; `validators_test`, `auth_error_test`, `auth_offline_test` |
| FR-02 | Capture with camera | `screens/scan_screen.dart` (`ImageSource.camera`) | Manual on device |
| FR-03 | Upload from gallery | `screens/scan_screen.dart` (`ImageSource.gallery`) | Manual on device |
| FR-04 | OCR text extraction | `services/ocr_service.dart` (ML Kit, rows rebuilt from boxes) | `receipt_parser_test` (`groupIntoRows`); manual |
| FR-05 | Parse names + prices for verification | `services/receipt_parser.dart`, S03 | `receipt_parser_test` (Keells/Cargills samples, real Pure Food bill) |
| FR-06 | Edit / add / delete items | `screens/review_screen.dart`, `widgets/item_edit_dialog.dart` | `review_screen_test`, `draft_receipt_provider_test` |
| FR-07 | Category per item, suggested | `services/category_suggester.dart`, S04 dropdown | `category_suggester_test`, `assign_test` |
| FR-08 | Create and select people | `screens/people_screen.dart`, S04 chips | `assign_test` (people group), `dialogs_test` |
| FR-09 | Item to one or more people | S04 `FilterChip`s, `DraftReceiptNotifier.togglePerson` | `assign_test` |
| FR-10 | Equal / exact / percentage | `services/split_calculator.dart` | `split_calculator_test` (incl. property-style invariant tests) |
| FR-11 | Totals: receipt, per person, per category | `widgets/split_summary_view.dart` (S05 + saved receipt) | `summary_screen_test`, `split_calculator_test` (summarize, breakdown) |
| FR-12 | History with search/filter | `screens/history_screen.dart`, `services/receipt_filter.dart` | `receipt_filter_test`, `history_screen_test` |
| FR-13 | Edit saved receipt and recalculate | `screens/receipt_detail_screen.dart` → `startEditing` → S03–S05 | `receipts_provider_test` (edit & recalculate), `receipt_mapper_test` (round trip) |
| FR-14 | Data per authenticated user | `supabase/schema.sql` (RLS), per-user repositories and caches | `supabase/test/rls_test.sql` (14 checks), `offline_repositories_test` (per-user cache) |

## Calculation rules

| Rule | Where enforced | Test |
|------|----------------|------|
| Single-person item → full amount | `SplitCalculator.equal` | "single person gets the full amount" |
| Shared item divided by method | `SplitCalculator.splitItem` | equal / exact / percentage groups |
| Assignments sum to item amount; remainder to first person | `SplitCalculator` + `save_receipt` check | property-style tests; `rls_test.sql` [3] |
| Items reconcile with receipt total; warn | S03 reconcile card, S05 save dialog | `review_screen_test`, `summary_screen_test` |
| Money as integer cents | `utils/money.dart`, `bigint` columns | `money_test` ("0.29" = 29 cents) |
