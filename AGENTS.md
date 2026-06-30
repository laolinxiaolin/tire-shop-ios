# Repository Guidelines

## Project Structure & Module Organization

This repository contains a native SwiftUI iOS app converted from an Expo/React Native app. App source lives in `TireShop/`, with the entry point in `TireShopApp.swift`. Core areas are split by purpose: API and auth in `APIClient.swift`, `Services.swift`, and `AuthStore.swift`; navigation in `RootViews.swift` and `Destinations.swift`; screens in `LoginView.swift`, `FeatureScreens.swift`, `DetailScreens.swift`, `OrderScreens.swift`, and `TransactionScreens.swift`; shared UI/theme helpers in `SharedViews.swift`, `Theme.swift`, and `NativeComponents.swift`; localization in `I18nStore.swift` and generated `I18nMessages.swift`.

The generated Xcode project is `TireShop.xcodeproj/`. `project.yml` is the XcodeGen-compatible spec. Helper scripts are in `scripts/`.

## Build, Test, and Development Commands

- `open TireShop.xcodeproj`: open the native app in Xcode.
- `node scripts/generate-xcodeproj.mjs`: regenerate `TireShop.xcodeproj` after Swift file changes.
- `node scripts/verify-swift-conversion.mjs`: check Swift structure, project references, and destination coverage.
- `node scripts/generate-i18n-swift.mjs`: regenerate Swift localization output.
- `xcodebuild -project TireShop.xcodeproj -scheme TireShop -destination 'platform=iOS Simulator,name=iPhone 16' build`: build from the command line when Xcode simulators are installed.

The README also references `pnpm swift:*` aliases, but this checkout does not currently include a `package.json`; use the direct `node` commands above unless package scripts are restored.

## Coding Style & Naming Conventions

Use Swift 5.10 and iOS 17 APIs. Follow the existing SwiftUI style: 4-space indentation, `PascalCase` for types and views, `camelCase` for properties/functions, and small focused structs/classes grouped by feature. Keep stores as `ObservableObject` classes and inject them through SwiftUI environment objects where existing screens do so. Avoid forced casts; verification checks for `as!`.

## Testing Guidelines

There is no dedicated XCTest target yet. For now, run `node scripts/verify-swift-conversion.mjs` before submitting changes and build the `TireShop` scheme in Xcode or with `xcodebuild`. When adding tests later, prefer XCTest files named after the unit under test, such as `APIClientTests.swift`, and keep test fixtures separate from app source.

## Commit & Pull Request Guidelines

Recent commits use short, imperative summaries, for example `Add 5 native modules toward web UI parity` and `Ignore node_modules and .expo leftovers`. Keep commits focused and outcome-oriented.

Pull requests should include a concise summary, verification steps run, linked issue or task context when available, and screenshots or screen recordings for UI changes. Note any regenerated files, especially `TireShop.xcodeproj/project.pbxproj` or `TireShop/I18nMessages.swift`.

## Security & Configuration Tips

Do not commit credentials, tokens, or local build artifacts. The API base URL is currently hardcoded in `TireShop/APIClient.swift`; discuss configuration strategy before changing production endpoints.
