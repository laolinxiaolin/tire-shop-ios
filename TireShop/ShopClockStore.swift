import SwiftUI

@MainActor
final class ShopClockStore: ObservableObject {
    @Published private(set) var timeZone: TimeZone
    @Published private(set) var loadedUserID: String?

    init() {
        timeZone = ShopClock.timeZone
    }

    var calendar: Calendar {
        ShopClock.calendar(in: timeZone)
    }

    func isReady(for userID: String) -> Bool {
        loadedUserID == userID
    }

    func refresh(for userID: String) async {
        let settings = try? await SettingsAPI().general()
        guard !Task.isCancelled else { return }
        if let settings {
            update(identifier: settings.timezone)
        }
        loadedUserID = userID
    }

    func resetSession() {
        loadedUserID = nil
    }

    func update(identifier: String) {
        guard let timeZone = TimeZone(identifier: identifier) else { return }
        ShopClock.persist(identifier)
        self.timeZone = timeZone
    }
}
