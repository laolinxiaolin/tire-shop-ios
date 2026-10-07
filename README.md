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

The September 2026 update follows the web repository through `1e479f4`:

- SKU wholesale prices can be set or cleared. Sale builders offer retail, wholesale, and the customer's latest invoiced/paid effective price, with its sale reference and date.
- Funds & Accounts can create separate cash accounts. Receivable/payable searches, totals, and aging use the server's complete results, with pagination and recoverable loading errors.
- Authorized staff can review and correct a purchase supplier with a required audit reason. Supplier purchase rows show payment status, counts, dates, and bill references; processing approvals are recognized.
- Expense receipts, payment-application documents, and payment proof support Camera, Photos, and Files. New expense forms retain their saved expense ID and remaining receipts when an attachment upload fails.
- API requests use the selected app language for server errors. The localization catalog generator preserves Xcode-extracted strings and existing translations.

These workflows require the corresponding backend endpoints. Wholesale pricing requires the web repository's `20260910120000_sku_wholesale_price` migration. Supplier correction uses `purchasing.supplier.change`; cash-account creation uses `accounting.manage`.

Regression tests live in `TireShopTests/`. Build and run the `TireShop` scheme's tests against an installed iOS simulator. Camera capture must also be checked on a physical iPhone; simulators offer Photos and Files.

The October 6 parity update reviews the latest six merged PRs in the shared web/API repository through `8754546`:

- [#494](https://github.com/laolinxiaolin/tire-shop/pull/494): Purchasing has a parent purchase-order register and detail, shared terms and documents, multi-container creation, packing-list copying, and reviewed membership changes with server versions. Goods remaining, supplier cash paid, bills due, and reversed/legacy settlement evidence stay separate. Containers retain their own receiving, inventory, and accounting workflows. Supplier and incoming views link to the parent and distinguish order/container counts.
- [#492](https://github.com/laolinxiaolin/tire-shop/pull/492) and [#493](https://github.com/laolinxiaolin/tire-shop/pull/493): New SKUs use one Model / Pattern field and let the API generate the model-first code, including embedded-ply handling and collision suffixes. Existing labels remain editable; this app does not rename the catalog.
- [#495](https://github.com/laolinxiaolin/tire-shop/pull/495): Customer analytics explains that GP comes from net sales minus booked COGS. Server profit values remain visible when verified Actual COGS is unavailable, subject to profit permissions; GP percentages remain unavailable on nonpositive net sales.
- [#489](https://github.com/laolinxiaolin/tire-shop/pull/489): Manual split tenders use one atomic receipt with net amounts and per-check deposit dates. Fee previews use decimal half-up rounding. An uncertain collection or failed post-collection refresh retires the form until balance and payment history refresh successfully. Quote confirmation retains the saved sale identity, recognizes already-completed confirmations, and ignores callbacks for replaced carts or login sessions.
- [#491](https://github.com/laolinxiaolin/tire-shop/pull/491): Fleet catalog pricing and customer price-level controls are already covered by the earlier native update and its regression tests.

Purchase-order document imports save independent copies in payment applications, and their displayed order/container references use the backend's frozen approval snapshots. Deploy migration `20261005000000_multi_container_purchase_orders` and the corresponding API before using the order workflows. The atomic receipt behavior requires the backend from #489. Version `1.0.15`, build `2026100601`, packages these changes together with the tax-data, customer-tax and sales-reporting updates below. App Store archives use the verified stable Xcode 27.0 toolchain (`27A266a`).

Focused regression coverage includes `PurchaseOrderTests`, `PurchaseOrderAPITests`, `PurchaseOrderDraftTests`, `ManualReceiptTests`, `SkuCreationContractTests`, and the analytics/Fleet tests. Localization and Xcode project files are regenerated from their checked-in sources.

The October 2 customer analytics update follows backend/web PRs [#485](https://github.com/laolinxiaolin/tire-shop/pull/485) and [#486](https://github.com/laolinxiaolin/tire-shop/pull/486), verified against `aa712265`:

- Open Customer Analytics from More/the sidebar, Customers, a customer profile, or Profile. Staff with only `customers.analytics.view` can use its standalone ranking and detail screens.
- Rankings use server totals and sorting, with search, shop-calendar periods, inclusive custom dates, historical price-level filters, pagination, and a matching Excel export. Customer drilldowns retain the period and level and show selected-period/lifetime totals plus separately paginated products and posted history.
- Cost and profit require `customers.profit.view` as well as the response's profit access flag. Missing cost evidence stays unavailable. History links open only when the server confirms the original invoice generation still exists and the user can view sales. Demo sessions cannot export.
- English/Chinese report notes explain the pretax recognition basis, return/reversal effects, differences from CRM, and incomplete historical coverage. Current customer level remains distinct from transaction-time level.

Deploy the corresponding analytics API and migration `20260928050000_customer_analytics_events`, run the backend's documented historical backfill, and grant the intended roles analytics/profit permissions before using these reports. The app displays the server's coverage status; it does not reconstruct missing history or infer historical cost. This update adds analytics independently of the earlier pricing and Freight workflow changes.

The September 27 update follows web/backend `c5d8147` (PRs #476 and #477):

- Sales lists, details, EOD and monthly reports identify Delivery, Pickup and Freight. Their raspberry/teal labels match the web's flat accent-bar design and light/dark palettes, with icons and text as well as color. Older sales without a fulfillment snapshot display Delivery. Freight drafts remain editable in the web app because their delivery-address and manual-tax controls are not present in this native release.
- Sales support fulfillment, multiple payment methods (including inactive historical methods), and custom date filters. Pagination, totals and Excel exports retain the same filters. Exported files and invoices use the backend's fulfillment formatting.
- Automatic tax refreshes when reopening shop-default drafts or delivery drafts whose customer street address is now empty. Explicit sale overrides remain intact; unchanged automatic rates retain saved rounding.
- Customer profiles show verified tax resolution, shop-default fallback and audited administrator overrides, including expiry dates and address review. Warehouses can save or clear their physical pickup address.
- Shop Settings gives administrators access to tax datasets: source checks, PDF/JSON uploads, findings and rate previews, validated publication, and SST ZIP/CSV import progress and retries. Imports remain on disk and use the backend's endpoint-specific size limits.

These screens require the corresponding deployed tax-data/customer-tax endpoints and migrations. Tests cover fulfillment/filter/export contracts, draft tax refresh, customer overrides, warehouse field clearing, tax imports and upload limits. `SaleFulfillmentSnapshotTests` captures English/Chinese labels in light/dark appearance and at accessibility text sizes.

Login survives closing and reopening the app. The access token and its server URL are stored together in the device-only Keychain; passwords and user permissions are not cached. Each cold launch validates the token through `GET /api/auth/session` and loads current user permissions before opening the app. A network or server failure keeps the credential for Retry; an expired/revoked session or explicit sign-out removes it. Changing servers never sends the saved token to the new server.

Deploy the backend's `GET /api/auth/session` endpoint and seven-day staff access-token lifetime before distributing this app change. No database migration or environment change is required. Until the endpoint is deployed, reopening offers password login with an explanation. New logins last one week; existing tokens retain their original expiration. Sessions are not renewed on reopening, and sign-out or server-side revocation ends access sooner. Users need to sign in once after updating because earlier app versions did not save a session. Authentication regression coverage is in `AuthStoreTests` and `SessionStorageTests`.

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

### Adaptive layouts and iPhone Duo

Toolbar actions provide titles and symbols. `AppOverflowMenu` uses the system
overflow on iOS 27 and retains a menu on older versions. The generated project
and `project.yml` enable `TIRESHOP_HAS_TOOLBAR_OVERFLOW_MENU` only for iPhoneOS
and Simulator 27.x SDKs; extend these SDK selectors when adopting a later major
SDK. Do not enable this flag with an SDK that lacks `ToolbarOverflowMenu`.
The deployment target remains iOS 17.

`AdaptiveLayoutTests` verifies grid reflow and sale price editor continuity at
different widths and text sizes. Full Duo validation additionally requires the
Xcode 27.1 Duo simulator: open/close and partially fold during sale editing,
check both orientations and Split View with the keyboard visible, and verify
navigation, draft values, payment state, and access to overflow actions. Even
column counts alone do not validate spacing around the folding region.

Edit the checked-in English and Simplified Chinese dictionaries in
`localization/messages.json`, then regenerate the Swift messages:

```sh
node scripts/generate-i18n-swift.mjs
```

The generator works from this standalone checkout and does not require the web
repository. Do not edit `TireShop/I18nMessages.swift` directly. Validate generated
output and the generator with:

```sh
node scripts/generate-i18n-swift.mjs --check
node --test scripts/generate-i18n-swift.test.mjs
```

To run the local conversion checks available without Xcode, run:

```sh
node scripts/verify-swift-conversion.mjs
bash scripts/verify-shop-clock.sh
```

## Fleet pricing parity (October 2, 2026)

- Product details, inventory rows, sorting, and SKU forms include Fleet alongside Wholesale and Retail. Standard-price edits require `pricing.manage`; unconfigured Fleet prices remain blank.
- Customer profiles and creation expose Wholesale/Fleet/Retail levels. Assigning levels or legacy percentage tiers requires `customers.priceLevel.manage` in addition to customer management.
- Quotes read `/pricing/policy` and use scoped `/pricing/quote-preview` responses when the server enables canonical customer pricing. The app preserves saved baselines and line identities, reviews customer changes and repricing before acceptance, and submits server price versions. Standard price, actual price, signed per-tire difference, and additional line adjustment remain distinct.
- The server rollout switch controls automatic customer-level pricing. This build does not activate the policy or populate missing prices/customer assignments. Legacy pricing choices remain available while the policy is disabled.
- An uncertain sale-creation response blocks automatic POST retries because the current backend does not provide idempotent sale creation. Staff can inspect saved Sales before resuming a persisted draft or starting over. Confirmation retries retain the known sale ID and reviewed pricing evidence.

Verification includes API payload and permission contracts, pricing-state regression tests, and English/Chinese phone and tablet visual fixtures. Version `1.0.14`, build `2026100202`, includes these Fleet controls.
