import SwiftUI
import UIKit
import XCTest
@testable import TireShop

/// Visual QA artifacts use in-memory check records and a session that rejects
/// network requests. No login, deposit, export, or date mutation is performed.
@MainActor
final class CheckScreensSnapshotTests: XCTestCase {
    func testCurrentCheckRegisterPhoneLayouts() async throws {
        let savedLanguage = UserDefaults.standard.object(forKey: "ts_lang")
        defer { restoreLanguage(savedLanguage) }

        for language in AppLanguage.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let i18n = I18nStore()
                i18n.setLanguage(language)
                let today = CheckDates.string(Date())
                let rows = sampleChecks(today: today)
                let store = ChecksListStore(
                    currentLoader: { UndepositedChecks(accountCode: "1010", items: rows) },
                    reportLoader: { _ in throw SnapshotError.unexpectedRequest },
                    dateSaver: { _, _ in throw SnapshotError.unexpectedRequest }
                )
                await store.load(asOf: today, today: today, canReport: true)
                XCTAssertTrue(store.ready)
                XCTAssertEqual(store.items.count, 4)

                let view = NavigationStack {
                    ChecksNativeView(store: store)
                }
                .environmentObject(fakeAuth())
                .environmentObject(i18n)
                .environment(\.locale, language.locale)
                .environment(\.calendar, ShopClock.calendar)
                .environment(\.timeZone, ShopClock.timeZone)
                .environment(\.colorScheme, scheme)

                let name = "checks-\(language.rawValue)-\(scheme == .dark ? "dark" : "light")"
                try await capturePhone(view, name: name, scheme: scheme, includeScrolled: true)
            }
        }
    }

    func testPlannedDateBackgroundsInBothLanguagesAndAppearances() async throws {
        let savedLanguage = UserDefaults.standard.object(forKey: "ts_lang")
        defer { restoreLanguage(savedLanguage) }

        for language in AppLanguage.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let i18n = I18nStore()
                i18n.setLanguage(language)
                let view = DateLabelExamples()
                    .environmentObject(i18n)
                    .environment(\.locale, language.locale)
                    .environment(\.colorScheme, scheme)
                let name = "check-date-values-\(language.rawValue)-\(scheme == .dark ? "dark" : "light")"
                try await capturePhone(view, name: name, scheme: scheme, includeScrolled: false)
            }
        }
    }

    private func sampleChecks(today: String) -> [UndepositedCheck] {
        let currentDate = CheckDates.date(today) ?? Date()
        let overdue = CheckDates.string(ShopClock.calendar.date(byAdding: .day, value: -7, to: currentDate) ?? currentDate)
        let future = CheckDates.string(ShopClock.calendar.date(byAdding: .day, value: 8, to: currentDate) ?? currentDate)
        let dates: [String?] = [overdue, today, nil, future]
        let names = ["North Coast Fleet Services", "Reliable Trucking", "Pacific Tire Wholesale", "Golden State Logistics"]
        return dates.enumerated().map { index, date in
            UndepositedCheck(
                id: "visual-check-\(index)", amount: [4820.50, 1250, 875.25, 2495][index],
                reference: "CHK-\(10421 + index)", note: index == 2 ? "One check covers two invoice payments." : nil,
                createdAt: "2026-09-01T16:00:00Z", methodName: "Check", invoiceRef: "INV-2026-00\(841 + index)",
                customerName: names[index], plannedDepositDate: date, receiptRef: "REC-2026-00\(412 + index)"
            )
        }
    }

    private func fakeAuth() -> AuthStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SnapshotNoNetworkProtocol.self]
        let auth = AuthStore(api: APIClient(session: URLSession(configuration: configuration)))
        auth.user = SessionUser(
            id: "visual-qa", email: "visual-qa@example.invalid", fullName: "Visual QA",
            roleId: "accountant", roleName: "Accountant", homeWarehouse: nil, isAdmin: false,
            permissions: ["accounting.view", "accounting.manage", "payments.collect"],
            approvalPermissions: [], mfaMethod: nil
        )
        auth.ready = true
        return auth
    }

    private func capturePhone<Content: View>(
        _ content: Content, name: String, scheme: ColorScheme, includeScrolled: Bool
    ) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: content)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        controller.view.layoutIfNeeded()
        try saveSnapshot(controller.view, name: name + "-top")

        if includeScrolled {
            let scroll = try XCTUnwrap(scrollableList(in: controller.view), "The fixture should produce a scrollable check list")
            // SwiftUI's lazy list replaces estimated heights as rows appear.
            // Recompute the bottom after each layout to include the last rows.
            for _ in 0..<3 {
                let bottom = max(-scroll.adjustedContentInset.top,
                                 scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
                try await Task.sleep(for: .milliseconds(150))
                controller.view.layoutIfNeeded()
                scroll.layoutIfNeeded()
            }
            try saveSnapshot(controller.view, name: name + "-bottom")
        }
    }

    private func scrollableList(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.isScrollEnabled,
           scroll.contentSize.height > scroll.bounds.height { return scroll }
        return view.subviews.lazy.compactMap { self.scrollableList(in: $0) }.first
    }

    private func saveSnapshot(_ view: UIView, name: String) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        XCTAssertGreaterThan(image.size.width, 300)
        XCTAssertGreaterThan(image.size.height, 700)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let folder = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
            .appendingPathComponent("CheckScreensVisualQA", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name + ".png")
        try XCTUnwrap(image.pngData()).write(to: file)
        print("CHECK_SCREEN_SNAPSHOT \(file.path)")
    }

    private func restoreLanguage(_ saved: Any?) {
        if let saved { UserDefaults.standard.set(saved, forKey: "ts_lang") }
        else { UserDefaults.standard.removeObject(forKey: "ts_lang") }
    }
}

private struct DateLabelExamples: View {
    @EnvironmentObject private var i18n: I18nStore
    private let today = "2026-09-12"
    private let examples: [(String, String?)] = [
        ("checks.overdue", "2026-09-11"),
        ("checks.dueToday", "2026-09-12"),
        ("checks.notDueYet", "2026-09-20"),
        ("checks.unscheduled", nil)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(i18n.t("accounting.cash.depositChecksTitle")).font(.title2.bold())
            ForEach(examples.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    Text(i18n.t(examples[index].0)).font(.headline)
                    Text(i18n.t("payment.plannedDepositDate")).font(.subheadline)
                    CheckDepositDateLabel(plannedDepositDate: examples[index].1, asOf: today)
                        .font(.subheadline)
                }
            }
            Spacer()
        }
        .foregroundStyle(Theme.text)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card)
    }
}

private enum SnapshotError: Error {
    case unexpectedRequest
}

private final class SnapshotNoNetworkProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: SnapshotError.unexpectedRequest)
    }
    override func stopLoading() {}
}
