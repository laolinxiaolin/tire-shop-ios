import SwiftUI
import UIKit

enum Theme {
    static let background = Color(lightHex: 0xf4f5f7, darkHex: 0x0f1115)
    static let card = Color(lightHex: 0xffffff, darkHex: 0x1a1d23)
    static let border = Color(lightHex: 0xe2e5ea, darkHex: 0x303640)
    static let text = Color(lightHex: 0x1a1d22, darkHex: 0xf3f4f6)
    static let muted = Color(lightHex: 0x6b7280, darkHex: 0x9ca3af)
    static let primary = Color(lightHex: 0x1f6feb, darkHex: 0x5d9bff)
    static let primaryText = Color.white
    static let danger = Color(lightHex: 0xd1242f, darkHex: 0xff6b6b)
    static let success = Color(lightHex: 0x1a7f37, darkHex: 0x63d587)

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xff) / 255
        let green = Double((hex >> 8) & 0xff) / 255
        let blue = Double(hex & 0xff) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    init(lightHex: UInt, darkHex: UInt) {
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: darkHex)
                : UIColor(hex: lightHex)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xff) / 255
        let green = CGFloat((hex >> 8) & 0xff) / 255
        let blue = CGFloat(hex & 0xff) / 255
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
