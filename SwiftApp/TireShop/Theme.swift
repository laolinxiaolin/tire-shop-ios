import SwiftUI

enum Theme {
    static let background = Color(hex: 0xf4f5f7)
    static let card = Color.white
    static let border = Color(hex: 0xe2e5ea)
    static let text = Color(hex: 0x1a1d22)
    static let muted = Color(hex: 0x6b7280)
    static let primary = Color(hex: 0x1f6feb)
    static let primaryText = Color.white
    static let danger = Color(hex: 0xd1242f)
    static let success = Color(hex: 0x1a7f37)

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
}
