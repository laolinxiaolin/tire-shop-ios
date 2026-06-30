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

The main tab and More-menu modules now have native SwiftUI data-loading screens for dashboard, inventory, sales, customers, work orders, returns, inventory counts, purchasing, money, accounting, cash accounts, FET, EOD, activity, approvals, users, roles, API keys, and shop settings. The larger transaction areas now have native first-pass flows for quote creation/confirmation, sale editing, SKU detail/create/edit, stock adjustment, Tap to Pay intent loading, return draft creation, customer creation, inventory count creation, and SKU/customer pickers.

## Using it in Xcode

Open `SwiftApp/TireShop.xcodeproj` in Xcode. The app entry point is `TireShopApp.swift`.

The checked-in project can be regenerated from the Swift sources:

```sh
pnpm swift:xcodeproj
```

If you prefer XcodeGen, `project.yml` is also included.

To refresh translations after editing `src/lib/i18n.tsx`, run:

```sh
pnpm swift:i18n
```

To run the local conversion checks available without Xcode, run:

```sh
pnpm swift:verify
```
