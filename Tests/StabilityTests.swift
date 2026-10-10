import Foundation
import Testing

/// Random and hostile inputs. Nothing may crash, hang, or produce out-of-range results.
struct StabilityTests {
    /// Deterministic random numbers, so a failure can be reproduced.
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    func checkInvariants(_ day: DayForecast, settings: ForecastSettings) {
        #expect((0...1).contains(day.cover))
        #expect(day.meetingCount >= 0 && day.longestStreak <= day.meetingCount)
        #expect(day.hours.count <= settings.workdayEndHour - settings.workdayStartHour + 1)
        #expect(day.hours.allSatisfy { (0...1.0001).contains($0.cover) })
        #expect(day.busy.allSatisfy { $0.start >= day.workday.start && $0.end <= day.workday.end && $0.start <= $0.end })
        #expect(zip(day.busy, day.busy.dropFirst()).allSatisfy { $0.end < $1.start }, "merged blocks must not overlap")
        if let clearing = day.nextClearing(after: day.workday.start, minimum: settings.minimumClearing) {
            #expect(day.workday.contains(clearing))
        }
    }

    @Test(arguments: ["UTC", "Europe/Dublin", "America/New_York", "Australia/Lord_Howe"])
    func randomCalendarsNeverBreakTheEngine(timeZone: String) {
        let calendar = calendar(timeZone)
        var random = SeededGenerator(state: 42)
        // Covers both daylight-saving changes of 2026.
        let base = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        for _ in 0..<1_500 {
            let day = base.addingTimeInterval(Double.random(in: 0...(365 * 86_400), using: &random))
            let settings = ForecastSettings(
                workdayStartHour: Int.random(in: -5...30, using: &random),
                workdayEndHour: Int.random(in: -5...30, using: &random)
            )
            let intervals = (0..<Int.random(in: 0...40, using: &random)).map { _ in
                let start = day.addingTimeInterval(Double.random(in: -86_400...172_800, using: &random))
                // Some are reversed or zero-length on purpose.
                return BusyInterval(start: start, end: start.addingTimeInterval(Double.random(in: -3_600...36_000, using: &random)))
            }
            let forecast = ForecastEngine.forecast(for: day, intervals: intervals, settings: settings, calendar: calendar)
            checkInvariants(forecast, settings: settings)
            _ = ForecastText.outlookLine(for: forecast, now: day, minimumClearing: settings.minimumClearing)
            _ = ForecastText.headline(for: forecast, now: day, season: .winter)
        }
    }

    @Test(arguments: [
        ("Europe/Dublin", 2026, 3, 29), ("Europe/Dublin", 2026, 10, 25),
        ("America/New_York", 2026, 3, 8), ("America/New_York", 2026, 11, 1),
        ("Australia/Lord_Howe", 2026, 4, 5),
    ])
    func daylightSavingDaysWork(timeZone: String, year: Int, month: Int, day: Int) {
        let calendar = calendar(timeZone)
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        for settings in [ForecastSettings(workdayStartHour: 0, workdayEndHour: 24), ForecastSettings()] {
            let start = calendar.startOfDay(for: date)
            let meeting = BusyInterval(start: start, end: start.addingTimeInterval(30 * 3_600))
            checkInvariants(ForecastEngine.forecast(for: date, intervals: [meeting], settings: settings, calendar: calendar), settings: settings)
        }
    }

    @Test func hugeCalendarStaysFast() {
        let calendar = calendar("UTC")
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        var random = SeededGenerator(state: 7)
        let intervals = (0..<20_000).map { _ in
            let start = day.addingTimeInterval(Double.random(in: 0...86_400, using: &random))
            return BusyInterval(start: start, end: start.addingTimeInterval(Double.random(in: 60...7_200, using: &random)))
        }
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = ForecastEngine.forecast(for: day, intervals: intervals, calendar: calendar)
            _ = ForecastEngine.outlook(after: day, days: 5, intervals: intervals, calendar: calendar)
        }
        #expect(elapsed < .seconds(2), "20,000 events took \(elapsed)")
    }

    @Test func hostileTitlesAreHandledSafely() {
        var random = SeededGenerator(state: 99)
        let samples = [
            String(repeating: "lunch ", count: 50_000),
            String(repeating: "a", count: 1_000_000),
            "\u{0000}lunch\u{0000}", "Lunch\u{202E}kaerb", "%@ %n %s lunch", "'; DROP TABLE events; -- lunch",
            "<script>alert(1)</script>", "🍔🍔🍔", "ＬＵＮＣＨ", "lunch\u{0301}", "\u{FEFF}gym", "\n\t\r",
        ]
        for title in samples { _ = BreakMatcher.isBreak(title) }
        for _ in 0..<5_000 {
            let scalars = (0..<Int.random(in: 0...80, using: &random)).compactMap { _ in
                Unicode.Scalar(UInt32.random(in: 0...0x10FFFF, using: &random))
            }
            _ = BreakMatcher.isBreak(String(String.UnicodeScalarView(scalars)))
        }
    }
}

/// What the widget hands to macOS (and macOS stores in its widget snapshots) must contain no text,
/// so no title or other event detail can end up there.
struct DataModelPrivacyTests {
    func strings(in value: Any, path: String = "forecast") -> [String] {
        if value is String || value is Substring || value is NSString || value is AttributedString {
            return [path]
        }
        return Mirror(reflecting: value).children.flatMap { child in
            strings(in: child.value, path: path + "." + (child.label ?? "?"))
        }
    }

    @Test func forecastsCarryNoText() {
        let now = Date()
        let intervals = SampleCalendar.intervals(around: now)
        let today = ForecastEngine.forecast(for: now, intervals: intervals)
        let outlook = ForecastEngine.outlook(after: now, days: 5, intervals: intervals)
        #expect(strings(in: today).isEmpty, "text found in: \(strings(in: today))")
        #expect(strings(in: outlook).isEmpty)
        #expect(strings(in: intervals).isEmpty)
        // The detector itself works: it finds text nested inside other values.
        #expect(!strings(in: (today, ["title": "Lunch"])).isEmpty)
    }
}
