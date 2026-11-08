# LocStore 🛍️

مدیریت انبار و صدور فاکتور پوشاک — کاملاً آفلاین، محلی و تک‌کاربره.

LocStore is a beautiful, modern, Material 3 clothing inventory & invoicing app for Android,
built with **Flutter** and **SQLite**. It is intentionally small, fast and local-first:
no backend, no accounts, no internet permission.

## ✨ Features

- **Products & variants** — each product has arbitrary variants/sizes (S/M/L, 38/40/42, …)
  with optional variant-level price overrides and per-variant stock.
- **Pricing rule** — variant custom price wins, otherwise the product default price.
- **Customers (v1.1)** — lightweight customer identities linked to invoices by ID.
  Created **inline while invoicing**: start typing a name, existing customers are
  suggested live (invoice count + total purchases), or one tap adds a new customer —
  without leaving the invoice form. Exact-name matches are reused (no accidental
  duplicates), but names are deliberately not unique (two people may share a name).
- **Customer profiles (v1.1)** — a dedicated Customers tab shows every customer with
  live aggregates (invoice count, total purchases, newest first), the full invoice
  history (opens the standard invoice details), profile editing (name/phone/notes),
  a one-tap *Create Invoice* with the customer pre-selected, and a guarded delete:
  customers with invoices can never be deleted, so history can never break.
- **Invoices** — sequential invoice numbers (starting at 1001), customer, Jalali date.
- **Payment status (v1.2)** — every invoice is either **پرداخت شده (Paid)** or
  **پرداخت نشده (Unpaid)** — no other states exist. New invoices default to *Unpaid*;
  the status is chosen on the Create Invoice screen (Material 3 segmented control),
  stays editable from Invoice Details, and is visible everywhere: invoice list,
  customer invoice history, home screen and the generated invoice image.
- **Invoice description (v1.2)** — an optional, free-text, multiline description belongs
  to the invoice itself (persisted in SQLite). It can be typed while creating the
  invoice, viewed and edited later from Invoice Details, and never occupies space when
  empty (lists/details/image skip it entirely).
- **Product sales history (v1.2)** — the Product Details screen shows an
  Invoice-History section organized **by variant/type** («XL — ۱۲ عدد فروش»), with one
  row per invoice: customer name, invoice number, quantity and Jalali date. Totals are
  computed live from invoice-item data (never stored counters), the same invoice with
  several variants of the product appears in each corresponding group, and tapping an
  entry opens the standard Invoice Details screen.
- **Price snapshots (critical rule)** — invoice items store the exact unit price, product
  name, color and variant name at sale time, and each invoice stores a historical
  customer-name snapshot. Later price/customer edits never alter history.
- **Atomic stock control** — creating an invoice decreases stock in one SQLite transaction;
  selling more than available is rejected with a clear message (and nothing is written).
- **Invoice deletion with restock** — deleting an invoice returns quantities to stock.
- **Invoice as image** — generates a professional receipt-style PNG (store name/logo,
  number, Jalali date, payment status, items, optional description, totals) from the
  historical snapshot and shares it via the Android share sheet (WhatsApp / Telegram / …).
- **Dashboard** — products count, total stock, today's invoices & sales, low-stock list,
  recent invoices, plus a one-tap *Create Invoice* action.
- **Archive instead of delete** — products referenced by historical invoices are archived
  so invoices stay readable forever; unused products can be hard-deleted.
- **Backup & restore** — validated SQLite-file backup (header + schema + integrity check),
  shared or saved through the Android file interface, restore with explicit confirmation.
- **Delete All Data** — strict multi-step flow: warning screen → type exactly
  `DELETE ALL DATA` → final confirmation. Atomic and undoable-by-design.
- **Persian-first UI** — full RTL, Vazirmatn font (bundled, OFL), Persian digits, Jalali
  calendar everywhere, configurable Toman/Rial display unit.
- **Theming** — 4 accent palettes × light/dark/system, Material 3 (dynamic color seeds).
- **Empty/loading/error states** on every screen; friendly Persian error messages.

## 🏛️ Architecture

```
lib/
├── main.dart               # boot: opens SQLite, loads settings
├── core/
│   ├── jalali.dart         # Jalali ⇄ Gregorian (port of jalaali-js, unit-tested)
│   ├── format.dart         # Persian digits, money formatting, input parsing
│   ├── theme.dart          # Material 3 design system (4 palettes × light/dark)
│   ├── validators.dart     # form validation (Persian messages)
│   └── services.dart       # service locator
├── data/
│   ├── database.dart       # AppDatabase: schema v3 (+ status/description), migrations, WAL
│   ├── product_repository.dart
│   ├── invoice_repository.dart   # transactional create/delete + stock sync
│   ├── customer_repository.dart  # CRUD, suggestions, live aggregates, delete guard
│   ├── settings_repository.dart  # key/value settings
│   ├── image_store.dart          # product photos & logo in app storage
│   └── backup_service.dart       # backup / validate / restore / delete-all
├── models/                 # Product, ProductVariant, Customer, Invoice, InvoiceItem, …
├── state/app_state.dart    # AppSettingsController (currency, theme, store info)
├── services/
│   ├── invoice_image.dart  # canvas-rendered receipt PNG (Vazirmatn, RTL)
│   └── share_service.dart  # Android share sheet
└── ui/
    ├── shell.dart          # bottom navigation (خانه / انبار / مشتری‌ها / فاکتورها / تنظیمات)
    ├── home/               # dashboard
    ├── inventory/          # list, details, edit, variant sheets
    ├── customers/          # customer field (inline create), list, profile, form sheet
    ├── invoices/           # list, details, create flow, product/variant pickers
    ├── settings/           # settings, store info, backup, danger zone
    └── widgets/            # empty states, badges, steppers, dialogs, …
```

### Database schema (SQLite, WAL)

| Table | Purpose |
| --- | --- |
| `products` | name, color, default price, image path, active (archive flag) |
| `variants` | per-product variants: name (unique per product), optional custom price, stock |
| `customers` | name (NOT unique by design), phone, notes, created_at |
| `invoices` | sequential number, `customer_id` → customers, historical customer-name snapshot, `status` ('Paid'/'Unpaid'), optional `description`, total, created_at |
| `invoice_items` | **snapshots**: product/variant names, color, quantity, unit price, line total |
| `settings` | currency unit, theme, palette, low-stock threshold, store info |

Schema migrations run automatically on app update — no manual backup/restore is ever
needed:

- **v1 → v2**: distinct invoice names are promoted into linked customer rows so existing
  history appears under Customers immediately.
- **v2 → v3**: invoices gain `status` (default `Unpaid`) and `description` (default `''`)
  via in-place `ALTER TABLE` — every historical row keeps its data and simply starts
  with the same defaults a new invoice would have.

Customer summaries and per-variant sales totals are always computed live from invoice
data (never stored counters).

Business rules (price fallback, stock ≥ 0, invoice⇄stock atomicity, snapshot immutability,
restock on delete, customer dedupe & delete guard) are centralized in the repositories and
covered by unit tests (`test/jalali_test.dart`, `test/format_test.dart`,
`test/business_test.dart`, `test/customer_test.dart`, `test/low_stock_test.dart`,
`test/backup_v1_test.dart`, `test/invoice_status_history_test.dart`) running against a
real SQLite engine, including the v1 → v2 → v3 migrations and the old-backup restore path.

## 🔨 Building

Requirements: Flutter (stable, 3.47+), Android SDK 36, JDK 17+.

```bash
flutter pub get
flutter test          # unit tests (jalali, formatting, business rules, migrations)
flutter analyze
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

To build a slim APK covering only modern devices (arm64 + x86_64):

```bash
flutter build apk --release --target-platform android-arm64,android-x64
```

The repository also contains a GitHub Actions workflow
(`.github/workflows/build-apk.yml`) that builds the release APK on every push.

### 🔑 Signing & app updates (important)

The project ships its own keystore — `android/locstore.keystore`
(alias `locstore`, password `locstore-signing`) — and **both the `debug` and
`release` build types are signed with it** (see `android/app/build.gradle.kts`).

This is what keeps over-the-top updates working: Android refuses to install an APK
whose signing key differs from the installed app («App not installed»). Because the
keystore lives in the repository, every rebuild — on this machine, another machine,
or GitHub Actions — produces the same app identity, so each new version installs
directly on top of the previous one with all data intact.

> Keep `locstore.keystore` and its password. Never delete or regenerate it:
> a regenerated key would break updates for existing installations.

If the currently installed version was signed with a *different* (lost) key, Android
will not let the new APK replace it directly. One-time migration path that preserves
all data: in the installed app open **تنظیمات ← پشتیبان‌گیری و بازیابی**, save the
backup file, uninstall the app, install the new APK, then restore the backup from the
same screen. Restored v1 databases are migrated to the current schema automatically.

## 📦 Backup format

A backup is a plain SQLite database file (`.db`). Restore validates the SQLite header,
required tables and `PRAGMA quick_check` before asking for confirmation; a safety copy of
the current data is kept until the swap succeeds.

## 📄 Licenses

- Code: MIT
- Font: [Vazirmatn](https://github.com/rastikerdar/vazirmatn) — SIL OFL 1.1 (see
  `assets/fonts/OFL.txt`)
