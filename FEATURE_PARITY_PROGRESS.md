# iOS ⇄ Web UI Feature Parity — Progress Tracker

Goal: bring the native SwiftUI app (`TireShop/`) to feature parity with the web UI (`apps/web`).
Backend (shared): `https://awstire.tail263731.ts.net/api`.
Full plan: `~/.claude/plans/let-s-enrich-the-feature-vectorized-oasis.md`.

**Status legend:** ⬜ not started · 🟨 in progress · ✅ done · ⏭️ deferred

**Web UI reference clone:** `…/scratchpad/web-repo` (ephemeral — re-clone
`https://github.com/laolinxiaolin/tire-shop` if gone). Spec source: `apps/web/lib/api.ts` +
`apps/web/app/<route>`.

---

## How to add a module (repeatable pattern)
1. `TireShop/Destinations.swift` → flip `isBuilt: true` on the destination key.
2. `TireShop/RootViews.swift:172` → add `case "key": SomeNativeView()` to `DestinationView`.
   Detail push? add an `AppRoute` case (`RootViews.swift:3`) + branch in `switch route` (`:118`).
3. `TireShop/Services.swift` → add `…API` struct (use `query([...])` helper).
4. `TireShop/Models.swift` → add `Codable` structs mirroring `apps/web/lib/api.ts`.
5. UI from `SharedViews.swift` (`AsyncContentView`, `StatGrid`, `RowLine`, `AppTextField`,
   `PrimaryButton`) + `NativeComponents.swift` (`FilterChips`, `PaymentSheetNativeView`).
6. i18n keys → `TireShop/I18nMessages.swift` (EN + zh-CN).

---

## Phase 0 — Tooling fixes (do first)
- ✅ `generate-i18n-swift.mjs` — NOT fixed; feature screens use plain strings (not i18n keys), so the broken generator isn't a blocker. New screens follow the plain-string convention.
- ✅ Fixed `scripts/generate-xcodeproj.mjs` paths. This script hand-writes `project.pbxproj` with an explicit file list — **must rerun after adding any .swift file**.
- ✅ Rewrote `scripts/verify-swift-conversion.mjs` — dropped obsolete RN-source comparisons (src/ gone); kept braces/forced-cast/built-destination/pbxproj checks.
- ✅ Confirmed the committed pbxproj is the real build input. Loop each change: `node scripts/generate-xcodeproj.mjs && node scripts/verify-swift-conversion.mjs`.

## Phase A — Build the 9 placeholder modules
(simplest → most complex)
- ✅ **Notifications** — `NotificationsNativeView` (list + auto mark-all-read). Models `AppNotification`/`NotificationsPage` + `NotificationsAPI`. In `PlaceholderModules.swift`.
- ✅ **Monthly Sales** — `MonthlySalesNativeView` (date range, 5 stat cards, line list). Models `MonthlySalesReport`/`Row`/`Summary` + `MonthlySalesAPI`.
- ✅ **Brand Info** — `BrandInfoNativeView` + `BrandEditorView` (bilingual add/edit, swipe-delete). Model `BrandInfo` + `BrandsAPI` + `BrandCreateInput`.
- ✅ **Tire Attributes** — `TireAttributesNativeView` (3 sections, add/rename/toggle/delete). Extended `TireAttributesAPI` (create/update/remove) + inputs.
- ✅ **Web Orders** — `OrdersListNativeView` (status segmented filter) + `OrderDetailNativeView` (confirm→Sale / cancel, links to created sale). Models `Order`/`OrderLine`/refs + `OrdersAPI`. New `OrderScreens.swift`; `AppRoute.orderDetail` added.
- ✅ **Commissions** — `CommissionsNativeView` (status filter, ledger, sale links, pagination). Models `CommissionEntry`/refs + `CommissionsAPI`.
- ✅ **Customer Relations (CRM)** — `customer-relations/page.tsx` + `EmailComposeModal.tsx` · NEW API `/crm/follow-ups`, `/crm/at-risk`, `/crm/templates`, `…/interactions`, `…/email` · `CustomerRelationsNativeView` (3 tabs + email compose)
- ✅ **Employees** — `EmployeesListNativeView` + `EmployeeDetailNativeView` + `EmployeeEditorView` (search/status filter, create/edit, linked user picker for admins, commission summary, recent commission links, payout history, pay-out action). Models `Employee`/`CommissionPayout` + `EmployeesAPI`.
- ✅ **Vendors** — `VendorsListNativeView` + `VendorDetailNativeView` + `VendorEditorView` + `VendorRefundEditorView` (search/category/status filters, create/edit/deactivate, detail summary, recent costs/expenses/refunds, refund record/reverse). Models `Vendor`/`VendorDetail`/refund rows + `VendorsAPI`.

> Naming flag: web `tiers/` = **Price Tiers**, NOT Tire Attributes → surface in Customer Account tab (Phase B), not a top-level module.

## Phase B — Admin edit/action flows (read-only → CRUD)
(✱ = endpoints already in `Services.swift`, UI only)
- ✅ **Work Orders detail** ✱ — task add/toggle/delete + status (`WorkOrdersAPI.addTask/toggleTask/deleteTask/update`)
- ✅ **Users** ✱ — create modal, role Picker, active toggle, reset password, reset MFA
- ✅ **Roles** ✱ — tri-state permission editor (off/approval/granted), create/edit/delete non-system
- ✅ **API Keys** ✱ — create w/ scope checkboxes, one-time plaintext reveal, revoke
- ✅ **Approvals** ✱ — PENDING/MINE/HISTORY tabs, approve/deny (note), cancel-own, detail sheet
- ⬜ **Shop Settings** — branding form ✱; general timezone ✱ + NEW `defaultTaxRate`; mail form (NEW `provider`/`secure`/`resendApiKey` on `MailPatchInput`); test mail ✱; NEW invoice-template; NEW logo upload/remove
- ✅ **Customer detail** — profile edit ✱, tax status ✱, documents ✱ (+NEW get/delete), NEW tags, NEW account/credit, NEW price tier, salesperson, storefront-access users, CRM cards

## Phase C — List search / filter / sort / pagination
(reuse `FilterChips`/`TireFilterOptions`; add shared paginator + search bar; replace hardcoded `pageSize: 50`)
- ⬜ **Inventory** — `q`, `category`, `position`, `sortBy/sortOrder`, paging
- ⬜ **Sales** — `q`, `status`, date-range presets (`from`/`to`), sort, paging, summary footer
- ⬜ **Returns** — `status` filter + **make rows tappable** → NEW `ReturnDetailNativeView` (`ReturnsAPI.get` ✱); void action (NEW)
- ⬜ **Purchasing** — `q` + `status` (Containers), `q` (Suppliers)
- ✅ **Work Orders** — `status` filter

## Phase D — Payments & invoices
- ⬜ **Invoice PDF** — QuickLook via `InvoicesAPI.downloadPDF` ✱ (QLPreviewController)
- ⬜ **Invoice email** — modal via `InvoicesAPI.email` ✱
- ⬜ **Quote PDF/email** — NEW `/sales/:id/quote-pdf`, `/sales/:id/quote-email`
- ⬜ **Payment reverse/refund** ✱ — `PaymentsAPI.reverse` (manual) / `refundProcessor` (card) buttons, gated `payments.reverse`
- ⬜ **Pay-link** — NEW `POST /invoices/:id/payment-link {email}` → share hosted Checkout URL
- ⏭️ **Stripe Terminal Tap-to-Pay** — heaviest; needs StripeTerminal SPM dep in `project.yml` + entitlement + on-device collect/confirm. Do LAST.

---

## Verification each phase
1. `node scripts/verify-swift-conversion.mjs` + `node scripts/generate-xcodeproj.mjs` (after Phase 0 path fixes).
2. Diff each screen's endpoints/fields against `apps/web/lib/api.ts` + the web page.
3. Build in Xcode (iOS 17+ sim), smoke-test vs live backend.
4. Permission gating matches web (`auth.has(...)` / `canActOrRequest`).

> Current Mac verification used iPhone 17 simulator because iPhone 16 is not installed.

---

## Session log
- 2026-06-30: Plan + tracker created; explored iOS app + web UI.
- 2026-06-30: Phase 0 tooling fixed (xcodeproj generator + verifier paths). Built Phase A simple modules: Notifications, Monthly Sales, Brand Info, Tire Attributes (all in new `TireShop/PlaceholderModules.swift` + models in `Models.swift` + APIs in `Services.swift`, wired in `Destinations.swift`/`RootViews.swift`). Plus **Web Orders** (`OrderScreens.swift`). Verifier green: 20 swift files, 26 built destinations. **Not yet compiled in Xcode** (no toolchain on Linux).
- 2026-06-30: Added **Commissions** native ledger from `employees/commissions/page.tsx`: status filter, paginated list, sale detail navigation, `GET /employees/commissions` API wrapper, and commission models. Verifier green: 20 swift files, 27 built destinations.
- 2026-06-30: Added **Employees** native module from `employees/page.tsx`, `[id]/page.tsx`, and `EmployeeModal.tsx`: list search/status filtering, create/edit sheet, detail profile/compensation, linked user picker, commission summary, recent commissions, payout history, and payout action. `xcodebuild` succeeded on iPhone 17 simulator.
- 2026-06-30: Added **Vendors** native module from `vendors/page.tsx` and `[id]/page.tsx`: list filters, create/edit/deactivate, spend summary, recent costs/expenses, refund history, refund record, and refund reverse. `xcodebuild` succeeded on iPhone 17 simulator.
- 2026-06-30: Added **Customer Relations (CRM)** native module: follow-up filters/actions, at-risk customer outreach, call logging, email compose with templates, template CRUD, CRM models, and `/crm` API wrappers.
- 2026-06-30: Added **Work Orders detail actions**: status/bay/notes editor, task add/toggle/delete, status-filtered list, and service wrapper fixes for the live `/work-orders` response shape.
- 2026-06-30: Added **Admin action flows**: Users create/edit/reset actions, Roles tri-state permission editor, API key create/reveal/revoke, and Approvals tabs/detail/decision actions.
- 2026-06-30: Added **Customer detail actions**: profile edit, tags, tax status, document upload/preview/delete, storefront logins, account/credit controls, price tier, salesperson, payment links for open invoices, and CRM relationship/interactions/follow-ups.
