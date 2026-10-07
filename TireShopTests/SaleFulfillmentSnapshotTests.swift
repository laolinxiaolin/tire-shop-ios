import SwiftUI
import UIKit
import XCTest
@testable import TireShop

/// Render the production fulfillment, status, and payment badges together to
/// verify their distinct shapes/colors in both languages and appearances.
@MainActor
final class SaleFulfillmentSnapshotTests: XCTestCase {
    func testSalesBadgesInBothLanguagesAppearancesAndAccessibleType() async throws {
        let savedLanguage = UserDefaults.standard.object(forKey: "ts_lang")
        defer {
            if let savedLanguage { UserDefaults.standard.set(savedLanguage, forKey: "ts_lang") }
            else { UserDefaults.standard.removeObject(forKey: "ts_lang") }
        }
        for language in AppLanguage.allCases {
            for scheme in [ColorScheme.light, .dark] {
                for largeType in [false, true] {
                    let i18n = I18nStore()
                    i18n.setLanguage(language)
                    let view = FulfillmentExamples()
                        .environmentObject(i18n)
                        .environment(\.locale, language.locale)
                        .environment(\.colorScheme, scheme)
                        .environment(\.dynamicTypeSize, largeType ? .accessibility3 : .large)
                    let name = "fulfillment-\(language.rawValue)-\(scheme == .dark ? "dark" : "light")-\(largeType ? "accessible" : "standard")"
                    try await capture(view, name: name, scheme: scheme)
                }
            }
        }
    }

    private func capture<Content: View>(_ view: Content, name: String, scheme: ColorScheme) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: view)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds, format: format).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertGreaterThan(image.size.width, 300)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let folder = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
            .appendingPathComponent("SaleFulfillmentVisualQA", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name + ".png")
        try XCTUnwrap(image.pngData()).write(to: file)
        print("SALE_FULFILLMENT_SNAPSHOT \(file.path)")
    }
}

private struct FulfillmentExamples: View {
    @EnvironmentObject private var i18n: I18nStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(i18n.t("salesList.col.fulfillment"))
                    .font(.title2.bold())
                row(ref: "INV-1026", customer: "Regional Freight Fleet", fulfillment: .freight, status: "INVOICED", methods: ["Check"])
                row(ref: "INV-1024", customer: "North Coast Fleet", fulfillment: .pickup, status: "PAID", methods: ["Cash"])
                row(ref: "INV-1025", customer: "Pacific Tire", fulfillment: .delivery, status: "INVOICED", methods: ["Card"])
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    private func row(ref: String, customer: String, fulfillment: SaleFulfillment, status: String, methods: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ref).font(.subheadline.bold())
            Text(customer).font(.body.weight(.semibold))
            Text("$480.00").font(.subheadline.bold().monospacedDigit())
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    SalesStatusBadge(status: status)
                    SalesPaymentMethodBadge(methods: methods)
                }
                VStack(alignment: .leading, spacing: 8) {
                    SalesStatusBadge(status: status)
                    SalesPaymentMethodBadge(methods: methods)
                }
            }
            SaleFulfillmentBadge(fulfillment: fulfillment)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
