# Conversion Status

## Converted to SwiftUI

- App entry, auth gate, secure token handling, cached user restore
- Login with MFA
- Navigation stack, tab shell, More menu, profile, customizable tabs
- Destination registry and permission filtering
- API client, multipart upload, authenticated download
- Shared API models and endpoint services
- Formatting and US phone helpers
- Language state, persisted language choice, translation lookup, and generated full English/Simplified Chinese message table
- Dashboard
- Inventory and SKU management
- SKU detail, create/edit, stock adjustment, add-to-sale
- Sales list, sale detail, new sale, edit sale
- Customer list, editable detail, picker, creation, documents, account controls, storefront users, and CRM relationship cards
- Work orders list/detail, status filtering, and task/status actions
- Returns list, returnable sale lookup, draft return creation
- Inventory counts list, detail, creation
- Purchasing/container list and detail
- Money, accounting, cash accounts, FET, EOD
- Activity, approvals, users, roles, API keys, and shop settings with branding, general, mail, invoice-template, and logo actions
- Notifications list and read-state sync
- Web orders list/detail with confirm and cancel actions
- Tire attributes management
- Brand info management
- Monthly sales report
- Employees list/detail with create/edit, commission summaries, payout history, and pay-out action
- Commissions ledger with status filtering and sale links
- Customer relations follow-ups, at-risk outreach, email compose, call logging, and template management
- Vendors list/detail with create/edit/deactivate, refund history, and refund record/reverse
- Service picker and quote cart state
- Tap to Pay intent loading
- Tire filter chips and manual payment sheet equivalents
- XcodeGen project specification for a native iOS app target
- Generated native `TireShop.xcodeproj` that includes all Swift sources
- Shared Xcode scheme for the generated native target
- I18n generator script that converts `src/lib/i18n.tsx` dictionaries to Swift
- Xcode project generator script for environments without XcodeGen
- Local conversion verifier for brace balance, route/API/destination coverage, translation parity, generated project/scheme coverage, package scripts, fallback placeholder count, and basic source hygiene

## Generic Placeholders

All original mobile placeholders have native replacements on the current conversion branches.

## Verification

`TireShop.xcodeproj` is generated and ready to open in Xcode. The latest local verification passed `scripts/verify-swift-conversion.mjs` and an Xcode command-line build on the available iPhone 17 simulator. Live-backend smoke testing is still the next manual gate.
