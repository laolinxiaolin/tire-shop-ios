import SwiftUI

extension SaleFulfillment {
    var titleKey: String { "sales.fulfillment.\(rawValue)" }

    var symbol: String {
        switch self {
        case .pickup: return "storefront"
        case .delivery: return "truck.box"
        case .freight: return "shippingbox"
        }
    }

    var badgeForeground: Color {
        switch self {
        case .pickup: return Color(lightHex: 0x00665E, darkHex: 0x80D5C9)
        case .delivery: return Color(lightHex: 0x88345E, darkHex: 0xF0ACCD)
        case .freight: return Color(lightHex: 0x705600, darkHex: 0xE8CA73)
        }
    }

    var badgeBackground: Color {
        switch self {
        case .pickup: return Color(lightHex: 0xE3F4F1, darkHex: 0x12332F)
        case .delivery: return Color(lightHex: 0xF9EAF2, darkHex: 0x3B2130)
        case .freight: return Color(lightHex: 0xFBF2D5, darkHex: 0x332B15)
        }
    }

    var badgeBorder: Color {
        switch self {
        case .pickup: return Color(lightHex: 0x007F73, darkHex: 0x49B8A8)
        case .delivery: return Color(lightHex: 0xAA4477, darkHex: 0xD57DA8)
        case .freight: return Color(lightHex: 0x997B1A, darkHex: 0xB89D50)
        }
    }
}

/// Historical sales without a fulfillment snapshot follow the Delivery default.
/// Icons and localized text keep the methods distinct without relying on color.
struct SaleFulfillmentBadge: View {
    @EnvironmentObject private var i18n: I18nStore
    let fulfillment: SaleFulfillment?

    private var method: SaleFulfillment { fulfillment ?? .delivery }

    var body: some View {
        Label(i18n.t(method.titleKey), systemImage: method.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(method.badgeForeground)
            .padding(.leading, 11)
            .padding(.trailing, 7)
            .padding(.vertical, 3)
            .background(method.badgeBackground)
            .overlay(alignment: .leading) {
                Rectangle().fill(method.badgeBorder).frame(width: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(i18n.t("salesList.col.fulfillment")): \(i18n.t(method.titleKey))")
    }
}
