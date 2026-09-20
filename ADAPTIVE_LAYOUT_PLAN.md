**TireShop adaptive layout implementation plan — iPhone Duo and iPad**

Scope agreed with the user: support both Sales/Inventory/Customers list-and-detail browsing and New Sale with a catalog beside the cart. Add native iPad support and use extra space to expose useful information and actions. This document is the implementation plan; application changes have not started.

The experience should preserve the current task as the device opens, closes, rotates, or enters a smaller window. Keep the iOS 17 deployment minimum. Use the iOS 27.1 SDK for full iPhone Duo support, with availability checks for newer APIs. The active local toolchain inspected during planning was Xcode 27.0.

The intended layouts are:

| Available app space | Browsing Sales, Inventory, or Customers | Creating a sale |
| --- | --- | --- |
| Compact, including a narrow iPad window | Pinned destinations and More; list opens selected details in a stack | Cart with product/service and customer pickers |
| Enough space for two useful panes, including an open Duo | Record list beside selected details; app navigation can collapse | Searchable catalog beside the cart; app navigation can collapse |
| Wide iPad window | Optional app sidebar, record list, and selected details | Optional app sidebar, larger catalog, and cart |

These are layout outcomes, not device-name rules. Use size classes, actual container dimensions, Dynamic Type, and system column behavior. Give working content priority when space shrinks: collapse the app sidebar before squeezing the two working panes, then fall back to a single-pane workflow. Native containers may present a column as an overlay. Do not permanently reserve a hinge gutter when the device is flat. This follows Apple's [split-view guidance](https://developer.apple.com/design/human-interface-guidelines/split-views) and [Duo preparation guidance](https://developer.apple.com/videos/play/tech-talks/111461/).

**1. Establish native iPad support and the shared navigation foundation.**

- Set the app and test targets to iPhone and iPad in `project.yml` and `scripts/generate-xcodeproj.mjs`, then regenerate `TireShop.xcodeproj`. The generator currently hardcodes iPhone-only targets. Preserve the orientations and multiple-scene declarations already present in `TireShop/Info.plist`.
- Use `DestinationRegistry` for the sidebar's existing groups and permission filtering, and `TabsStore` for favorites. Keep one favorites model. On supported systems, use the native adaptive tab/sidebar presentation; keep compatible tabs and More on iOS 17. Wide iPad navigation should expose permitted modules directly and remain hideable. Apple's [sidebar guidance](https://developer.apple.com/design/human-interface-guidelines/sidebars) supports this adaptable approach.
- Introduce a scene-owned navigation model for the selected destination, selected record per browsing module, and deeper detail routes. Extract the route rendering and authorization currently private to `NavigationShell` so compact and expanded presentations use the same routing rules.
- Keep each feature's search, filter, sorting, pagination, and scroll state in a stable owner above any presentation changes. Avoid putting every feature's data in one global navigation store.
- Map module links from Home, More, and other screens into the same destination model. Handle links from customer details to a sale deliberately so returning restores customer context. Clear inaccessible selections when permissions or authentication change.
- Preserve the check-reminder banner's root-screen behavior and single ownership. Opening Checks from the banner must work from every layout without duplicating the banner in detail panes.

Primary files: `RootViews.swift`, `Destinations.swift`, `TireShopApp.swift`, a focused new navigation-state/shell file, the project spec and generator.

**2. Build the three browsing workspaces, starting with Sales.**

- Use `NavigationSplitView` for each list/detail relationship. Highlight the selected record and keep that selection stable through folding, resizing, and sidebar changes. Use an intentional selection prompt before a record is chosen; show an appropriate unavailable state if the selected record is deleted or becomes inaccessible.
- Sales: keep search, status/date filters, sorting, summaries, and pagination in the list pane; show the selected sale in the detail pane. Preserve deeper edit, return, and payment navigation. Best Sellers remains an alternate Sales view with a useful full content layout, rather than an unrelated empty detail pane.
- Inventory: show searchable stock rows with the existing warehouse/filter/export behavior and a selected SKU's detail. Keep batch-selection state separate from the single record selected for details. Product browsing and adding products to a sale must have explicit, different row actions.
- Customers: show the customer list beside the existing profile/account/history detail. Reuse existing customer actions and permission checks.
- Refresh the affected record and list summary after edits or payments while preserving filters and position. A late response for a previously selected record must not replace the current detail.

Primary files: `FeatureScreens.swift`, `DetailScreens.swift`, `CustomerDetailScreens.swift`, and focused workspace/state files. Reuse existing detail views and API calls.

**3. Turn New Sale into a catalog-and-cart workspace.**

- Use one stable workspace owner for search context, unfinished price strings, focus, warehouse initialization, stock checks, errors, and submission state. Retain the existing scene-scoped `QuoteStore` as the source of customer, cart, tax, and creation/confirmation retry data.
- In wide layouts, show a larger catalog pane with Tires/Services, search, filters, stock, and price choices. Keep the cart independently scrollable, with customer and warehouse context, quantity/price editing, and totals plus Confirm visible near the cart. In compact layouts, retain the cart-first flow with pickers. Both layouts expose the same actions.
- Extract the existing inventory/service/customer picker content from its dismissal behavior. An embedded catalog adds an item and stays open; a compact picker may return to the cart. Reuse pricing and availability rules rather than creating a second catalog implementation.
- Resolve warehouse selection once at workspace entry. Today New Sale and the inventory picker choose different defaults, which would race if both mounted together. Preserve an existing valid selection, otherwise use the sale's employee-home/default rule.
- Keep catalog and cart price-history requests in separate stable scopes initially; the current price-history store supports only one active request and must not be shared unchanged between competing consumers.
- Freeze all cart-changing actions during confirmation, including embedded catalog additions and customer/warehouse changes. Preserve the existing idempotency key, original creation input, and confirmation retry behavior. Confirm continues to create/confirm the sale; payment continues from sale details.
- Prevent Edit Sale from reseeding the shared quote over an active New Sale draft. Reuse the existing draft-discard flow where available; otherwise offer discard-or-cancel before switching editing context. Layout transitions themselves never discard or resubmit a draft.
- Evaluate `ArrangementView` for the content pairing on iOS 27.1, with shared content and a compatible adaptive layout on older systems. Keep it inside navigation and outside scrolling content. It does not replace routing. Apple's [arrangement guidance](https://developer.apple.com/videos/play/tech-talks/111463/) describes this distinction.

Primary files: `TransactionScreens.swift`, `FeatureScreens.swift`, `QuoteStore.swift` where ownership requires adjustment, and a focused sale-workspace file.

**4. Make the larger layout useful throughout the app.**

- Reflow Home's fixed two-column metrics into a content-aware grid. Arrange related dashboard sections side by side where each remains readable.
- In detail panes, group related information into columns where it improves scanning. Keep long forms at readable widths, align numeric fields, and avoid stretching buttons and text fields across an entire iPad.
- Expand filters and secondary information when space permits; retain compact menus at smaller widths. Keep lists and forms independently scrollable within their own panes. Use the existing `EvenColumnGrid` and identity-preserving `SaleItemHeaderLayout` where appropriate.
- Audit every existing destination for clipping, oversized empty space, large text, and usability in a narrow pane. The initial dedicated list/detail conversions are Sales, Inventory, and Customers; other modules use the shared shell and adaptive content sizing.
- Preserve English/Chinese localization and light/dark appearance. Update the localization sources through the existing workflow and preserve unrelated catalog edits.

**5. Complete native presentation and input behavior.**

- Let system tabs, toolbars, and overflow adapt to Duo's vertical controls. Keep foreground controls inside the correct pane's safe area; handle unequal left/right insets. Use fold-aware APIs only for custom controls that need them, with small contextual movements. Do not relocate entire scrolling lists around the fold. See Apple's [Duo design guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo).
- Review customer/payment sheets, popovers, document sharing, printing, camera/photo/file pickers, and keyboard avoidance on iPad. Anchor UIKit presentations to the initiating view and window, including presentations launched from a split detail pane.
- Review the global keyboard and presenter helpers: they currently search connected windows and can choose the wrong window once multiple windows are visible. Keep navigation, drafts, and focus per window; preserve the existing authentication scope.
- Make Tap to Pay visibility and warm-up use the existing reader-capability checks. Surface supported payment choices on iPad and verify Duo support with the SDK; do not assume contactless acceptance from screen size or OS version. Stripe documents compatible iPhones and excludes beta iOS from live Tap to Pay support. Separate simulator layout testing from payment verification on supported hardware and a supported release OS. [Stripe device guidance](https://docs.stripe.com/terminal/payments/setup-reader/tap-to-pay?platform=ios)
- Check keyboard traversal, pointer interaction, VoiceOver selection, and accessible labels for symbol-only actions. Add useful keyboard shortcuts for search and New Sale where they fit the existing behavior.

Primary files: `AdaptiveToolbar.swift`, `SharedViews.swift`, `NativeComponents.swift`, `RootViews.swift`, and the affected screens.

**6. Validate behavior as well as screenshots.**

| Scenario | Required result |
| --- | --- |
| Select a sale, close/reopen Duo, then navigate back | Same selected sale and logical back path; no duplicate detail stack |
| Resize iPad through wide, intermediate, and compact widths | Columns adapt without losing filters, selection, or scroll position |
| Type an incomplete price, then resize or change the sidebar | Draft text survives; one editor remains; focus is preserved where feasible |
| Add multiple tires/services with search beside the cart | Search stays open; quantities, price choices, stock limits, and totals remain correct |
| Change customer/warehouse or enter Edit Sale | Correct pricing/tax/stock context; no race or silent draft overwrite |
| Resize during creation/confirmation retry | No duplicate request or cart mutation; the existing retry can complete |
| Show keyboard, large text, or system multitasking | Primary actions remain reachable; working panes collapse before becoming unusable |
| Open two windows and edit independently | Navigation, quote drafts, presentations, and focus remain in the correct window |
| Open an iPad payment/document flow | Supported payment choices and correctly anchored presentations |

Extend the existing `AdaptiveLayoutTests`, `CheckReminderLayoutTests`, and fixture-based snapshot coverage for these meaningful regressions. Preserve existing pricing, preflight, and submission tests. Test a regular iPhone, Duo in its main poses and both multitasking positions, iPad mini, and 11-inch/13-inch iPad windows, including the oldest supported runtime where available. Capture compact, two-pane, and wide-sidebar screenshots in both languages.

During implementation, regenerate the Xcode project after source-file additions, run `node scripts/verify-swift-conversion.mjs`, build the app for the selected iPhone and iPad simulators, and run the `TireShopTests` target through the shared scheme. Obtain available simulator identifiers from Xcode rather than assuming device names. Full Duo visual acceptance uses Xcode 27.1's simulator. No live customer transaction is needed for layout verification.

Delivery order: shared shell and native iPad target; Sales as the first complete split workflow; Inventory and Customers; New Sale workspace; remaining screen/presentation adjustments; final device and regression checks. Each stage should leave the existing compact workflows usable and provide a concrete UI to review.
