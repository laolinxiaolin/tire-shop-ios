import SwiftUI
import UIKit
import XCTest
@testable import TireShop

/// Exercises production layout containers with local content and a real native
/// text field. The fixture has no stores, credentials, or network requests.
@MainActor
final class AdaptiveLayoutTests: XCTestCase {
    func testGridReflowsIntoEvenColumnsWithoutOverlap() async throws {
        let host = try AdaptiveFixtureHost()
        defer { host.close() }

        for (width, expectedColumns) in [(260.0, 1), (500.0, 2), (700.0, 4), (260.0, 1)] {
            try await host.resize(to: width)
            let columns = try assertGridFits(host)
            XCTAssertEqual(columns, expectedColumns, "Unexpected columns at \(width) points")
        }
    }

    func testPriceEditorKeepsIdentityFocusAndDraftAcrossReflow() async throws {
        let host = try AdaptiveFixtureHost()
        defer { host.close() }
        try await host.resize(to: 260)
        try assertHeaderFits(host, stacked: true)

        let field = try XCTUnwrap(host.textFields.first)
        XCTAssertEqual(host.textFields.count, 1)
        XCTAssertTrue(field.becomeFirstResponder())
        field.text = "12345.67"
        field.sendActions(for: .editingChanged)
        try await host.settle()
        XCTAssertEqual(host.model.price, "12345.67")

        for (width, stacked, name) in [
            (700.0, false, "adaptive-layout-wide"),
            (260.0, true, "adaptive-layout-narrow")
        ] {
            try await host.resize(to: width)
            let current = try XCTUnwrap(host.textFields.first)
            XCTAssertEqual(host.textFields.count, 1, "Reflow must not mount duplicate price editors")
            XCTAssertTrue(current === field, "Resizing should preserve the native editor")
            XCTAssertTrue(current.isFirstResponder, "Resizing should preserve editing focus")
            XCTAssertEqual(current.text, "12345.67")
            XCTAssertEqual(host.model.price, "12345.67")
            try assertHeaderFits(host, stacked: stacked)
            _ = try assertGridFits(host)
            try saveSnapshot(host, name: name)
        }
    }

    func testAccessibilityTextStacksHeaderAndGridSafely() async throws {
        let host = try AdaptiveFixtureHost()
        defer { host.close() }
        host.model.dynamicTypeSize = .accessibility3
        host.model.price = "12345.67"
        try await host.resize(to: 320)

        try assertHeaderFits(host, stacked: true)
        XCTAssertEqual(try assertGridFits(host), 1)
        let price = try XCTUnwrap(host.probe.frames["price"])
        XCTAssertGreaterThan(price.height, 44, "The price editor must grow with accessibility text")
        let field = try XCTUnwrap(host.textFields.first)
        XCTAssertEqual(field.text, "12345.67")
        try saveSnapshot(host, name: "adaptive-layout-accessibility")
    }

    @discardableResult
    private func assertGridFits(_ host: AdaptiveFixtureHost) throws -> Int {
        let grid = try XCTUnwrap(host.probe.frames["grid"])
        let cards = try (0..<4).map { try XCTUnwrap(host.probe.frames["stat-\($0)"]) }
        for card in cards {
            XCTAssertGreaterThan(card.width, 0)
            XCTAssertGreaterThan(card.height, 0)
            XCTAssertTrue(grid.insetBy(dx: -1, dy: -1).contains(card), "Card \(card) exceeds grid \(grid)")
        }
        for first in cards.indices {
            for second in cards.indices where second > first {
                assertNoOverlap(cards[first], cards[second])
            }
        }
        let firstRowY = try XCTUnwrap(cards.first).minY
        let columns = cards.filter { abs($0.minY - firstRowY) < 1 }.count
        XCTAssertTrue(columns == 1 || columns.isMultiple(of: 2))
        XCTAssertLessThanOrEqual(grid.maxX, host.controller.view.bounds.width + 1)
        return columns
    }

    private func assertHeaderFits(_ host: AdaptiveFixtureHost, stacked: Bool) throws {
        let header = try XCTUnwrap(host.probe.frames["header"])
        let description = try XCTUnwrap(host.probe.frames["description"])
        let price = try XCTUnwrap(host.probe.frames["price"])
        XCTAssertTrue(header.insetBy(dx: -1, dy: -1).contains(description))
        XCTAssertTrue(header.insetBy(dx: -1, dy: -1).contains(price))
        XCTAssertLessThanOrEqual(header.maxX, host.controller.view.bounds.width + 1)
        assertNoOverlap(description, price)
        if stacked {
            XCTAssertGreaterThanOrEqual(price.minY, description.maxY + Theme.Space.md - 1)
        } else {
            XCTAssertEqual(price.minY, description.minY, accuracy: 1)
        }
    }

    private func assertNoOverlap(_ first: CGRect, _ second: CGRect) {
        let intersection = first.intersection(second)
        XCTAssertTrue(intersection.isNull || intersection.width < 1 || intersection.height < 1,
                      "Layout elements overlap: \(first), \(second)")
    }

    private func saveSnapshot(_ host: AdaptiveFixtureHost, name: String) throws {
        let content = try XCTUnwrap(host.probe.frames["content"])
        let size = CGSize(width: host.controller.view.bounds.width, height: ceil(content.maxY))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.controller.view.drawHierarchy(in: host.controller.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AdaptiveLayoutVisualQA", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name + ".png")
        try XCTUnwrap(image.pngData()).write(to: file)
        print("ADAPTIVE_LAYOUT_SNAPSHOT \(file.path)")
    }
}

@MainActor
private final class AdaptiveFixtureHost {
    let model = AdaptiveFixtureModel()
    let probe = AdaptiveFrameProbe()
    let controller: UIHostingController<AdaptiveLayoutFixture>
    private let window: UIWindow
    private let previousKeyWindow: UIWindow?

    init() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        controller = UIHostingController(rootView: AdaptiveLayoutFixture(model: model, probe: probe))
        controller.safeAreaRegions = []
        let container = UIViewController()
        window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.addChild(controller)
        container.view.addSubview(controller.view)
        controller.didMove(toParent: container)
        controller.view.backgroundColor = .white
    }

    var textFields: [UITextField] {
        func collect(_ view: UIView) -> [UITextField] {
            (view as? UITextField).map { [$0] } ?? view.subviews.flatMap(collect)
        }
        return collect(controller.view)
    }

    func resize(to width: CGFloat) async throws {
        controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 1800)
        try await settle()
    }

    func settle() async throws {
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(180))
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        controller.view.layoutIfNeeded()
    }

    func close() {
        controller.view.endEditing(true)
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }
}

private final class AdaptiveFixtureModel: ObservableObject {
    @Published var price = "215.00"
    @Published var dynamicTypeSize = DynamicTypeSize.large
}

private final class AdaptiveFrameProbe {
    var frames: [String: CGRect] = [:]
}

private struct AdaptiveFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct AdaptiveFrameReporter: View {
    let name: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: AdaptiveFramesKey.self, value: [name: proxy.frame(in: .named("adaptive-fixture"))])
        }
    }
}

private struct AdaptiveLayoutFixture: View {
    @ObservedObject var model: AdaptiveFixtureModel
    let probe: AdaptiveFrameProbe

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Sale").font(.title2.bold())
            AdaptivePriceHeaderFixture(model: model)
            Divider()
            Text("Inventory summary").font(.headline)
            EvenColumnGrid(minimumColumnWidth: 145) {
                ForEach(0..<4) { index in
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(["Available tires", "Reserved tires", "Inventory value", "Active SKUs"][index])
                            .font(.caption).foregroundStyle(Theme.muted)
                        Text(["1,284", "96", "$248,450", "327"][index])
                            .font(.title3.bold()).foregroundStyle(Theme.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Space.md)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .overlay { RoundedRectangle(cornerRadius: Theme.Radius.sm).stroke(Theme.border) }
                    .background(AdaptiveFrameReporter(name: "stat-\(index)"))
                }
            }
            .background(AdaptiveFrameReporter(name: "grid"))
        }
        .padding(16)
        .background(AdaptiveFrameReporter(name: "content"))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(name: "adaptive-fixture")
        .onPreferenceChange(AdaptiveFramesKey.self) { probe.frames = $0 }
        .background(Theme.background)
        .environment(\.dynamicTypeSize, model.dynamicTypeSize)
        .environment(\.colorScheme, .light)
        .environment(\.locale, Locale(identifier: "en_US"))
        .ignoresSafeArea()
    }
}

private struct AdaptivePriceHeaderFixture: View {
    @ObservedObject var model: AdaptiveFixtureModel
    @FocusState private var editing: Bool
    @ScaledMetric(relativeTo: .body) private var descriptionWidth: CGFloat = 160
    @ScaledMetric(relativeTo: .body) private var priceWidth: CGFloat = 120

    var body: some View {
        SaleItemHeaderLayout(spacing: Theme.Space.md, minimumDescriptionWidth: descriptionWidth, minimumPriceWidth: priceWidth) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Michelin Defender LTX M/S 265/70R17").font(.body.weight(.semibold))
                Text("Tire").font(.subheadline).foregroundStyle(Theme.muted)
            }
            .background(AdaptiveFrameReporter(name: "description"))
            HStack(spacing: 2) {
                Text("$").foregroundStyle(Theme.muted)
                Text(model.price.isEmpty ? "0" : model.price)
                    .font(.body.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .hidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .overlay {
                        TextField("0", text: $model.price)
                            .keyboardType(.decimalPad)
                            .focused($editing)
                            .multilineTextAlignment(.trailing)
                            .font(.body.monospacedDigit().weight(.semibold))
                            .accessibilityLabel("Unit price")
                    }
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.sm)
            .frame(minHeight: 44)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay { RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(editing ? Theme.primary : Theme.border) }
            .background(AdaptiveFrameReporter(name: "price"))
        }
        .background(AdaptiveFrameReporter(name: "header"))
    }
}
