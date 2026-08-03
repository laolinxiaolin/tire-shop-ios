import SwiftUI

#if DEBUG
import UIKit

fileprivate struct DebugLayoutSnapshot: Hashable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let safeTop: Int
    let safeLeading: Int
    let safeBottom: Int
    let safeTrailing: Int

    init(proxy: GeometryProxy) {
        let frame = proxy.frame(in: .global)
        x = Self.scaled(frame.minX)
        y = Self.scaled(frame.minY)
        width = Self.scaled(frame.width)
        height = Self.scaled(frame.height)
        safeTop = Self.scaled(proxy.safeAreaInsets.top)
        safeLeading = Self.scaled(proxy.safeAreaInsets.leading)
        safeBottom = Self.scaled(proxy.safeAreaInsets.bottom)
        safeTrailing = Self.scaled(proxy.safeAreaInsets.trailing)
    }

    private static func scaled(_ value: CGFloat) -> Int {
        Int((value * 100).rounded())
    }

    var description: String {
        let values = [x, y, width, height, safeTop, safeLeading, safeBottom, safeTrailing]
            .map { String(format: "%.2f", Double($0) / 100) }
        return "frame=(x:\(values[0]),y:\(values[1]),w:\(values[2]),h:\(values[3])) "
            + "safe=(t:\(values[4]),l:\(values[5]),b:\(values[6]),r:\(values[7]))"
    }
}

@MainActor
enum DebugLayoutLog {
    static func event(_ message: String) {
        print("[LAYOUT] event \(message)")
    }

    fileprivate static func geometry(_ name: String, snapshot: DebugLayoutSnapshot) {
        let window = activeWindow
        let windowDescription: String
        if let window {
            windowDescription = "window=(w:\(window.bounds.width),h:\(window.bounds.height)) "
                + "windowSafe=(t:\(window.safeAreaInsets.top),l:\(window.safeAreaInsets.left),"
                + "b:\(window.safeAreaInsets.bottom),r:\(window.safeAreaInsets.right))"
        } else {
            windowDescription = "window=none"
        }
        print("[LAYOUT] geometry \(name) \(snapshot.description) \(windowDescription)")
    }

    static func keyboard(_ name: String, notification: Notification) {
        let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        let orphaned = KeyboardSession.isOrphaned(notification)
        print("[LAYOUT] keyboard \(name) endFrame=\(String(describing: frame)) "
            + "duration=\(String(describing: duration)) orphaned=\(orphaned) "
            + "firstResponder=\(KeyboardSession.debugFirstResponderDescription)")
    }

    private static var activeWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

private struct DebugLayoutProbe: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { proxy in
                let snapshot = DebugLayoutSnapshot(proxy: proxy)
                Color.clear
                    .allowsHitTesting(false)
                    .task(id: snapshot) {
                        DebugLayoutLog.geometry(name, snapshot: snapshot)
                    }
            }
        }
    }
}

private struct DebugKeyboardDiagnostics: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) {
                DebugLayoutLog.keyboard("willShow", notification: $0)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) {
                DebugLayoutLog.keyboard("willChangeFrame", notification: $0)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) {
                DebugLayoutLog.keyboard("willHide", notification: $0)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) {
                DebugLayoutLog.keyboard("didHide", notification: $0)
            }
    }
}

extension View {
    func debugLayoutProbe(_ name: String) -> some View {
        modifier(DebugLayoutProbe(name: name))
    }

    func debugKeyboardDiagnostics() -> some View {
        modifier(DebugKeyboardDiagnostics())
    }
}
#else
@MainActor
enum DebugLayoutLog {
    static func event(_ message: String) {}
}

extension View {
    func debugLayoutProbe(_ name: String) -> some View { self }
    func debugKeyboardDiagnostics() -> some View { self }
}
#endif
