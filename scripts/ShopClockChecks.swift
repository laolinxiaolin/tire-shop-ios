import Foundation

@main
enum ShopClockChecks {
    static func main() throws {
        let iso = ISO8601DateFormatter()
        let newYork = try requireTimeZone("America/New_York")
        let losAngeles = try requireTimeZone("America/Los_Angeles")
        let utc = try requireTimeZone("UTC")

        let evening = try requireDate("2026-08-03T02:00:00Z", formatter: iso)
        check(ShopClock.dayString(from: evening, in: newYork) == "2026-08-02", "New York evening stays on Aug 2")
        check(ShopClock.dayString(from: evening, in: losAngeles) == "2026-08-02", "Los Angeles evening stays on Aug 2")
        check(ShopClock.dayString(from: evening, in: utc) == "2026-08-03", "UTC has crossed into Aug 3")

        let pickedDay = try requireDate("2026-08-03T04:00:00Z", formatter: iso)
        check(
            ShopClock.date(fromDayString: "2026-08-03", in: newYork) == pickedDay,
            "A picked New York day anchors at local midnight"
        )

        let beforeDstEnd = try requireDate("2026-11-01T04:00:00Z", formatter: iso)
        let afterDstEnd = try requireDate("2026-11-02T05:00:00Z", formatter: iso)
        check(
            ShopClock.date(fromDayString: "2026-11-01", in: newYork) == beforeDstEnd,
            "DST-end day uses the pre-transition offset"
        )
        check(
            ShopClock.date(fromDayString: "2026-11-02", in: newYork) == afterDstEnd,
            "The following day uses the post-transition offset"
        )

        let invalid = ShopClock.resolveTimeZone("Not/A_Time_Zone")
        check(
            invalid.identifier == ShopClock.defaultTimeZoneIdentifier,
            "Invalid settings fall back to the backend default"
        )

        print("ok shop clock timezone and DST checks")
    }

    private static func requireTimeZone(_ identifier: String) throws -> TimeZone {
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw CheckError(message: "Missing time zone \(identifier)")
        }
        return timeZone
    }

    private static func requireDate(_ value: String, formatter: ISO8601DateFormatter) throws -> Date {
        guard let date = formatter.date(from: value) else {
            throw CheckError(message: "Could not parse \(value)")
        }
        return date
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError("fail: \(message)")
        }
    }
}

private struct CheckError: Error {
    let message: String
}
