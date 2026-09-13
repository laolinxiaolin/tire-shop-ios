# Tire Shop SwiftUI Conversion

This folder is the SwiftUI starting point for converting the Expo/React Native app to native iOS.

## What is converted

- `App.tsx` -> `TireShopApp.swift` and `RootGateView`
- `state/auth.tsx` -> `AuthStore.swift`
- `lib/api.ts` auth/token behavior -> `APIClient.swift`
- `navigation/destinations.tsx` and `state/tabs.tsx` -> `Destinations.swift`
- `navigation/RootNavigator.tsx` -> `RootViews.swift`
- `LoginScreen.tsx` -> `LoginView.swift`
- shared theme/UI primitives -> `Theme.swift` and `SharedViews.swift`
- shared format/phone helpers -> `Formatters.swift`
- language state and translation lookup -> `I18nStore.swift`
- generated English/Simplified Chinese messages -> `I18nMessages.swift`
- most API response/input types -> `Models.swift`
- endpoint groups from `lib/api.ts` -> `Services.swift`
- primary list/summary screens -> `FeatureScreens.swift`
- stack detail/create/picker routes -> `DetailScreens.swift`
- sales, SKU, stock adjustment, Tap to Pay, and return transaction flows -> `QuoteStore.swift` and `TransactionScreens.swift`
- shared tire filters and manual payment sheet -> `NativeComponents.swift`
- generated native Xcode project -> `TireShop.xcodeproj`
- shared Xcode scheme -> `TireShop`

The main tab and More-menu modules now have native SwiftUI data-loading screens for dashboard, inventory, sales, customers, customer relations, work orders, returns, inventory counts, purchasing, vendors, money, accounting, cash accounts, FET, EOD, employees, commissions, activity, approvals, users, roles, API keys, and shop settings. Work orders include status filtering plus task and status actions. The larger transaction areas now have native first-pass flows for quote creation/confirmation, sale editing, SKU detail/create/edit, stock adjustment, Tap to Pay intent loading, return draft creation, customer creation, inventory count creation, employee create/edit, commission payout, vendor create/edit/refunds, CRM outreach, and SKU/customer pickers.

The native cheque workflows also follow web/backend [PR #465](https://github.com/laolinxiaolin/tire-shop/pull/465):

- Invoice and receivables cheque collection require a valid planned calendar date before any payment is submitted, including split tenders.
- Finance → Checks shows current undeposited payments, inline date editing, historical cutoff reports and localized Excel sharing. Date edits and background refreshes preserve row order; Refresh sorts again. Historical rows remain read-only and retain deleted-payment identities supplied by the register.
- In-app reminders show due, overdue and missing-date entries, refreshing each minute, on foregrounding, and after cheque mutations.
- Deposit checks opens the funds transfer form with account 1010 → 1020 presets. Future or undated selections require an additional review that resets when the draft changes. Deposit records show every invoice allocation, including reversed deposits, with pagination and full details.

Planned date values in the Checks list and deposit picker share the Sales status palette: future or unset dates use Paid blue, and due or overdue dates use Invoiced amber. Historical lists compare dates with the selected cutoff. Labels and date text retain their normal colors.

Deploy backend migration `20260912100000_check_deposit_dates_and_register` before using these clients. Existing cheque dates remain unset until entered. Checks access requires `payments.collect` or `accounting.view`; history and Excel require `accounting.view`, date edits require `payments.collect` or `accounting.manage`, and deposits require `accounting.manage`. Native returns currently create drafts only; the exchange-posting API model accepts the cheque date for a future posting UI.

Cheque regressions: run the `TireShop` XCTest suite and `bash scripts/verify-check-deposit-draft.sh`.

## Using it in Xcode

Open `TireShop.xcodeproj` in Xcode. The app entry point is `TireShopApp.swift`.

The checked-in project can be regenerated from the Swift sources:

```sh
node scripts/generate-xcodeproj.mjs
```

If you prefer XcodeGen, `project.yml` is also included.

To refresh translations after editing `src/lib/i18n.tsx`, run:

```sh
node scripts/generate-i18n-swift.mjs
```

To run the local conversion checks available without Xcode, run:

```sh
node scripts/verify-swift-conversion.mjs
bash scripts/verify-shop-clock.sh
```
