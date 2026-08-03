# Sales Initial-Layout Failure — Root Cause and Fix

## Status

**Fixed.** Root cause identified and confirmed on the physical device with the
console attached.

- Broken TestFlight version: **1.0.4 (2026080301)** — predates this fix
- Reproduction device: physical **iPhone 15 Pro Max**, named `iPhone (10)` in Xcode
- Device CoreDevice ID: `2A675D74-F91F-56E8-A23E-044DE5245E7F`
- Device OS: **iOS 27.0**
- Bundle ID: `com.tireforceus.tireshop`

The iOS 27 Simulator does not reproduce the failure, because credentials get
inserted through accessibility without opening the software keyboard. All
verification below is from the physical device.

## User-visible behavior (before the fix)

After a fresh launch and login, the Sales screen opened with the totals summary
strip around the middle of the screen, only about three sales rows above it, a
large blank region below the strip, and no working scroll below the strip.
Backgrounding and foregrounding the app repaired the layout.

## Root cause

Two independent defects compounded. Both had to be fixed.

### 1. An orphaned keyboard session inflates the root safe area

Submitting the login form arms iOS's AutoFill "save this password?" flow. A
successful sign-in sets `auth.user`, which immediately swaps `LoginView` for the
authenticated hierarchy — so AutoFill ends up presenting its hidden save
controller into a hierarchy that no longer exists:

```text
Keyboard cannot present view controllers
(attempted to present <UIKeyboardHiddenViewController_Save ...>)
```

The presentation fails, but the keyboard session is left half-open. UIKit posts
`keyboardWillShow` with a 320–347pt frame and **never posts the matching hide**,
because there is no first responder to resign:

```text
keyboard willShow endFrame=(0,612,430,320)
keyboard willShow endFrame=(0,585,430,347)
```

SwiftUI's keyboard avoidance honors those insets, so the root safe-area bottom
goes 34 → 320 → 347 and the root shrinks 839 → 553 → 526. Backgrounding the app
tears down the stale keyboard state, which is why foregrounding "repaired" it.

The physical window is correct throughout — only the SwiftUI safe area is wrong:

```text
window=(w:430,h:932)
windowSafe=(t:59,l:0,b:34,r:0)
```

### 2. `GeometryReader` hard-frames welded the bad size in place

An earlier fix attempt wrapped `RootNavigatorView` and `NavigationShell` in
`GeometryReader` and framed them to the proxy size:

```swift
GeometryReader { geometry in
    TabView { … }.frame(width: geometry.size.width, height: geometry.size.height)
}
```

A `GeometryReader` reports the size **proposed to it**, which was already
keyboard-shrunk (553/526). Hard-framing to that value converted a soft,
recoverable safe-area inset into a locked frame.

This is why the `.ignoresSafeArea(.keyboard, edges: .bottom)` attempts appeared
to fail: the modifier was applied to the `TabView`/`NavigationStack` *inside* the
`GeometryReader`, so the reader above it still measured 553 and pinned the child
there regardless. The log line recorded as proof —"`RootNavigator` could remain
full-height; nested `NavigationShell` still collapsed to 526" — is the signature
of a `GeometryReader` hard-frame, not of a failed `ignoresSafeArea`.

The two workarounds cancelled each other out, which sent the earlier
investigation toward the `.oneTimeCode` dead end.

## The fix

### `TireShop/RootViews.swift`

1. **Removed both `GeometryReader` hard-frames** from `RootNavigatorView` and
   `NavigationShell`. They fixed nothing and prevented recovery.

2. **Added `KeyboardSession`**, which detects and closes the orphaned session:

   - `isOrphaned(_:)` — true when a keyboard geometry notification describes a
     keyboard moving on screen while nothing in the app is first responder. It
     finds the first responder by sending a selector up the responder chain with
     `UIApplication.sendAction(_:to:nil:from:for:)`, capturing the responder in a
     box passed as `sender`, and checks whether it is a `UITextInput`. Keyboards
     parked at or below the window's bottom edge are treated as leaving, not
     arriving.
   - `dismissOrphanedSession()` — the orphaned session cannot be dismissed with
     `endEditing`, because there is nothing to resign. Instead it adds a hidden
     stand-in `UITextField` with an empty `inputView`, makes it first responder,
     resigns it, and removes it. That gives UIKit a real responder to attach to
     and then run its normal teardown, which posts the `keyboardWillHide` that
     never arrived. The empty `inputView` means no keyboard becomes visible.

   `RootNavigatorView` observes `keyboardWillShow`/`keyboardWillChangeFrame` and
   reclaims the session whenever an orphan is detected.

### `TireShop/LoginView.swift`

3. **Reverted `textContentType` from `.oneTimeCode` back to `.password`.** The
   `.oneTimeCode` experiment was a workaround with a permanent cost — it breaks
   Password AutoFill and iCloud Keychain save/fill for every user on a screen
   staff hit constantly — and it only suppressed one trigger rather than fixing
   the defect. `KeyboardSession` neutralizes the orphaned session regardless of
   what triggers it.

4. **Added `KeyboardSession.dismiss()` on submit.** SwiftUI's `@FocusState` is
   only applied on the next update pass; an explicit app-wide `endEditing(true)`
   resigns immediately, so AutoFill can start and finish its save-password work
   while the login hierarchy is still mounted.

### Structural footer change (kept)

Sales and Best Sellers attach their totals strip as a `VStack` sibling of a
flexible `List` rather than via `.safeAreaInset(edge: .bottom)`. This was made
during the earlier investigation. It does not fix the root problem, but it stops
the footer from splitting list rows and is reasonable on its own, so it stays.

## Verification

Measured on `iPhone (10)`, iOS 27, Debug build with the console attached.

Before — broken:

```text
NavigationShell[Sales] h=526 safeBottom=347
SalesContent          h=367 safeBottom=347
SalesList             h=308.33
SalesFooter           y=526.33 h=58.67
```

After — matches the known-good geometry exactly:

```text
[LAYOUT] event orphanedKeyboardDetected
[LAYOUT] event dismissOrphanedSession ran
Keyboard cannot present view controllers (<UIKeyboardHiddenViewController_Save>)

NavigationShell[Sales] h=790 safeBottom=83
SalesContent          h=631 safeBottom=83
SalesList             h=572.33
SalesFooter           y=790.33 h=58.67
```

The orphan is still created by iOS — the "cannot present" message still appears —
but it is now detected and torn down before it can reach the layout.

**Verification coverage so far:** two cold logins (one on the intermediate build,
one on the final build), each with the orphan detected and reclaimed and Sales
measuring 790/631/572.33/790.33 with no bad geometry at any point. The standing
bar in this document is three cold logins on the shipping build; **one** of those
three has been done on the final build. Two more cold-login runs should be done
before a TestFlight upload.

### Detection is safe against false positives

A self-check run on the device confirmed the responder-chain probe behaves, and
critically that it **fails closed**:

```text
selfCheck withField=UITextField(textInput)   # focused field is found
selfCheck afterRemove=nil                    # nothing focused → nil, not the window
```

Every legitimate keyboard in the app logs `orphaned=false` with
`firstResponder=UIKitTextField(textInput)`, so normal keyboard avoidance is
untouched. Keyboard-hide notifications carry `endFrame.minY == 932` (the window
height) and are correctly ignored as "leaving".

## Instrumentation

Debug-only instrumentation lives in `TireShop/LayoutDiagnostics.swift`, attached
from `TireShopApp.swift`, `RootViews.swift`, `FeatureScreens.swift`, and
`LoginView.swift`. It logs scene phase, keyboard notifications (including
`orphaned=` and the resolved `firstResponder=`), window bounds/insets, and frames
for `SceneRoot`, `RootGate`, `RootNavigator`, each `NavigationShell`,
`SalesScreen`, `SalesContent`, `SalesList`, and `SalesFooter`.

It is wrapped in `#if DEBUG`; Release/TestFlight builds print nothing.

Build and install the diagnostic app:

```sh
node scripts/generate-xcodeproj.mjs
xcodebuild \
  -project TireShop.xcodeproj \
  -scheme TireShop \
  -configuration Debug \
  -destination 'platform=iOS,id=2A675D74-F91F-56E8-A23E-044DE5245E7F' \
  -derivedDataPath /tmp/tire-shop-ios-diagnostics \
  build

xcrun devicectl device install app \
  --device 2A675D74-F91F-56E8-A23E-044DE5245E7F \
  /tmp/tire-shop-ios-diagnostics/Build/Products/Debug-iphoneos/TireShop.app

xcrun devicectl device process launch \
  --device 2A675D74-F91F-56E8-A23E-044DE5245E7F \
  --terminate-existing \
  --console \
  com.tireforceus.tireshop
```

Reproduction steps: cold-launch (`AuthStore.restore()` intentionally clears the
session, so login is required every time), enter credentials with the **physical
on-screen keyboard**, submit, then open Sales.

## Relevant source files

- `TireShop/RootViews.swift` — `KeyboardSession`, `RootGateView`, `RootNavigatorView`, `NavigationShell`
- `TireShop/LoginView.swift` — login fields, focus, submit flow
- `TireShop/AuthStore.swift` — successful login immediately sets `user`, replacing `LoginView`
- `TireShop/FeatureScreens.swift` — `SalesListNativeView`, list/footer layout
- `TireShop/TireShopApp.swift` — app root and scene phase
- `TireShop/LayoutDiagnostics.swift` — debug-only measurements and keyboard events

## Notes for future work

- Do not reintroduce `GeometryReader` + `.frame(proxy.size)` around the root or
  the navigation shells. It reads a size that already includes transient insets
  and makes them permanent.
- If a similar phantom inset shows up elsewhere, check `orphaned=` in the console
  before reaching for `.ignoresSafeArea(.keyboard)` — ignoring the region on a
  `TabView` does **not** propagate into the tab pages, which was verified on
  device during this investigation.
- A deeper structural option, not needed now, is decoupling authentication from
  committing `auth.user` so the login view can settle before the root swaps.

## Repository/worktree notes

The worktree contains the date/timezone parity work requested earlier, Sales
layout changes, diagnostics, and a version bump. It is intentionally dirty and
should not be reset or have unrelated changes discarded.

Current version settings:

- `MARKETING_VERSION = 1.0.4`
- `CURRENT_PROJECT_VERSION = 2026080301`

The TestFlight upload for 1.0.4 (2026080301) succeeded but predates this fix, so
it is still broken. A new build is needed.
