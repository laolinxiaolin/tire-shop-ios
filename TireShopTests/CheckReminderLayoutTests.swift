import SwiftUI
import UIKit
import XCTest
@testable import TireShop

@MainActor
final class CheckReminderLayoutTests: XCTestCase {
    func testReminderDismissalReclaimsContentSpaceWithoutNavigation() async throws {
        let fixture = try await makeFixture(width: 393, textSize: .large)
        defer { fixture.close() }
        try saveSnapshot(fixture, name: "check-reminder-before-dismiss")
        let contentTop = fixture.probe.contentTop
        let barBefore = try assertReminderReservesContentSpace(fixture)

        // In-process hosting doesn't expose SwiftUI's accessibility actions.
        // Exercise the same store action as the close button and inspect its layout effect.
        fixture.store.dismissForToday()
        try await settle(fixture)
        try saveSnapshot(fixture, name: "check-reminder-after-dismiss")

        XCTAssertFalse(fixture.store.isBannerVisible)
        XCTAssertLessThan(fixture.probe.contentTop, contentTop - 40, "Dismissal must return the banner's space to content")
        let navigation = try XCTUnwrap(navigationController(in: fixture.controller))
        XCTAssertEqual(navigation.viewControllers.count, 1, "Dismissal must not open the check register")
        let barAfter = navigation.navigationBar.convert(navigation.navigationBar.bounds, to: nil)
        XCTAssertEqual(barBefore.minY, barAfter.minY, accuracy: 1, "The reminder must not move the navigation bar")
        XCTAssertLessThanOrEqual(fixture.probe.contentTop, barAfter.maxY + 24)
    }

    func testNarrowLargeTextReminderIsScopedToRootContent() async throws {
        let fixture = try await makeFixture(width: 320, textSize: .accessibility1)
        defer { fixture.close() }
        try saveSnapshot(fixture, name: "check-reminder-narrow-large-text")
        _ = try assertReminderReservesContentSpace(fixture)
        let navigation = try XCTUnwrap(navigationController(in: fixture.controller))

        fixture.probe.showDetail = true
        try await settle(fixture)
        try saveSnapshot(fixture, name: "check-reminder-pushed-detail")
        XCTAssertEqual(navigation.viewControllers.count, 2)
        XCTAssertFalse(navigation.navigationBar.isHidden)
        XCTAssertNotNil(navigation.navigationBar.backItem)
        XCTAssertFalse(navigation.navigationBar.topItem?.hidesBackButton ?? true)
        let bar = navigation.navigationBar.convert(navigation.navigationBar.bounds, to: nil)
        XCTAssertTrue(fixture.probe.detailTop.isFinite)
        XCTAssertGreaterThanOrEqual(fixture.probe.detailTop, bar.maxY - 1)
        XCTAssertLessThanOrEqual(fixture.probe.detailTop, bar.maxY + 24, "A pushed screen must not retain the root reminder's inset")
        XCTAssertTrue(fixture.store.isBannerVisible, "Navigating away should not need to dismiss the reminder")

        fixture.probe.showDetail = false
        try await settle(fixture)
        XCTAssertEqual(navigation.viewControllers.count, 1)
        _ = try assertReminderReservesContentSpace(fixture)
    }

    func testFailedReminderDismissalReclaimsSpaceAtAccessibilitySize() async throws {
        let fixture = try await makeFixture(width: 320, textSize: .accessibility3, failed: true)
        defer { fixture.close() }
        try saveSnapshot(fixture, name: "check-reminder-failure-large-text")
        XCTAssertTrue(fixture.store.failed)
        _ = try assertReminderReservesContentSpace(fixture)
        let contentTop = fixture.probe.contentTop
        fixture.store.dismissForToday()
        try await settle(fixture)
        try saveSnapshot(fixture, name: "check-reminder-failure-dismissed")
        XCTAssertFalse(fixture.store.isBannerVisible)
        XCTAssertLessThan(fixture.probe.contentTop, contentTop - 40)
    }

    private func makeFixture(width: CGFloat, textSize: DynamicTypeSize, failed: Bool = false) async throws -> ReminderFixture {
        let suiteName = "CheckReminderLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let store = CheckReminderStore(defaults: defaults, currentDay: { "2026-09-15" }) {
            if failed { throw ReminderFixtureError.unexpectedRequest }
            return CheckReminderSummary(
                asOf: "2026-09-15", timezone: "America/New_York", dueTodayCount: 2,
                overdueCount: 1, unscheduledCount: 1, totalAmount: 6240.50, items: []
            )
        }
        store.reset(for: "reminder-layout-fixture")
        await store.refresh()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReminderNoNetworkProtocol.self]
        let auth = AuthStore(api: APIClient(session: URLSession(configuration: configuration)))
        auth.user = SessionUser(
            id: "reminder-layout-fixture", email: "fixture@example.invalid", fullName: "Layout Fixture",
            roleId: "accountant", roleName: "Accountant", homeWarehouse: nil, isAdmin: false,
            permissions: ["accounting.view"], approvalPermissions: [], mfaMethod: nil
        )
        auth.ready = true
        let savedLanguage = UserDefaults.standard.object(forKey: "ts_lang")
        let i18n = I18nStore()
        i18n.setLanguage(.en)
        if let savedLanguage { UserDefaults.standard.set(savedLanguage, forKey: "ts_lang") }
        else { UserDefaults.standard.removeObject(forKey: "ts_lang") }
        let probe = ReminderFixtureProbe()
        let content = NavigationShell(title: "Dashboard") {
            ReminderRootContent(probe: probe)
        }
        .environmentObject(auth)
        .environmentObject(i18n)
        .environmentObject(store)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.dynamicTypeSize, textSize)
        .environment(\.colorScheme, .light)
        let fixture = try ReminderFixture(content: AnyView(content), store: store, probe: probe, width: width)
        try await settle(fixture)
        return fixture
    }

    private func assertReminderReservesContentSpace(_ fixture: ReminderFixture) throws -> CGRect {
        let navigation = try XCTUnwrap(navigationController(in: fixture.controller))
        let bar = navigation.navigationBar
        XCTAssertFalse(bar.isHidden)
        let barFrame = bar.convert(bar.bounds, to: nil)
        XCTAssertTrue(fixture.store.isBannerVisible)
        XCTAssertTrue(fixture.probe.contentTop.isFinite)
        XCTAssertGreaterThanOrEqual(fixture.probe.contentTop, barFrame.maxY + 44,
                                    "Reminder space must be reserved below navigation")
        return barFrame
    }

    private func navigationController(in controller: UIViewController) -> UINavigationController? {
        if let navigation = controller as? UINavigationController { return navigation }
        return controller.children.lazy.compactMap { self.navigationController(in: $0) }.first
    }

    private func settle(_ fixture: ReminderFixture) async throws {
        fixture.controller.view.setNeedsLayout()
        fixture.controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(450))
        fixture.controller.view.layoutIfNeeded()
    }

    private func saveSnapshot(_ fixture: ReminderFixture, name: String) throws {
        let view = try XCTUnwrap(fixture.controller.view)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CheckReminderVisualQA", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name + ".png")
        try XCTUnwrap(image.pngData()).write(to: file)
        print("CHECK_REMINDER_SNAPSHOT \(file.path)")
    }
}

@MainActor
private final class ReminderFixture {
    let controller: UIHostingController<AnyView>
    let store: CheckReminderStore
    let probe: ReminderFixtureProbe
    private let window: UIWindow
    private let previousKeyWindow: UIWindow?

    init(content: AnyView, store: CheckReminderStore, probe: ReminderFixtureProbe, width: CGFloat) throws {
        self.store = store
        self.probe = probe
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        controller = UIHostingController(rootView: content)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 852)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }
}

private final class ReminderFixtureProbe: ObservableObject {
    @Published var showDetail = false
    var contentTop = CGFloat.nan
    var detailTop = CGFloat.nan
}

private struct ReminderRootContent: View {
    @ObservedObject var probe: ReminderFixtureProbe

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your dashboard content")
                    .font(.headline)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { probe.contentTop = $0 }
                Text("Navigation and page controls stay available while a deposit reminder is shown.")
                Button("Open fixture details") { probe.showDetail = true }
                    .buttonStyle(.borderedProminent)
                ForEach(1..<5) { number in
                    Text("Dashboard row \(number)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .navigationDestination(isPresented: $probe.showDetail) {
            Text("Detail content has the full available height.")
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { probe.detailTop = $0 }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle("Fixture details")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private enum ReminderFixtureError: Error {
    case unexpectedRequest
}

private final class ReminderNoNetworkProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: ReminderFixtureError.unexpectedRequest) }
    override func stopLoading() {}
}
