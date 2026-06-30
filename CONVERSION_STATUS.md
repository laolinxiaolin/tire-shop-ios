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
- Customer list, detail, picker, creation
- Work orders list and detail
- Returns list, returnable sale lookup, draft return creation
- Inventory counts list, detail, creation
- Purchasing/container list and detail
- Money, accounting, cash accounts, FET, EOD
- Activity, approvals, users, roles, API keys, shop settings
- Notifications list and read-state sync
- Web orders list/detail with confirm and cancel actions
- Tire attributes management
- Brand info management
- Monthly sales report
- Commissions ledger with status filtering and sale links
- Service picker and quote cart state
- Tap to Pay intent loading
- Tire filter chips and manual payment sheet equivalents
- XcodeGen project specification for a native iOS app target
- Generated native `TireShop.xcodeproj` that includes all Swift sources
- Shared Xcode scheme for the generated native target
- I18n generator script that converts `src/lib/i18n.tsx` dictionaries to Swift
- Xcode project generator script for environments without XcodeGen
- Local conversion verifier for brace balance, route/API/destination coverage, translation parity, generated project/scheme coverage, package scripts, fallback placeholder count, and basic source hygiene

## Still Generic Placeholder By Design

These destinations exist in the original mobile registry without concrete screen components, so the Swift app keeps them navigable with the same generic placeholder behavior:

- Vendors
- Customer Relations
- Employees

## Verification Needed Outside This Environment

This workspace does not have the Swift toolchain or Xcode command line tools installed. `SwiftApp/TireShop.xcodeproj` is generated and ready to open in Xcode, where the app should be compiled as the next verification gate.
