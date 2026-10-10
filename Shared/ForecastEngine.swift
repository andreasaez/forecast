import Foundation

/// Weather, from calmest to wildest.
enum Condition: Int, CaseIterable, Comparable, Sendable {
    case clear, partlyCloudy, cloudy, rain, storm

    static func < (lhs: Condition, rhs: Condition) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct ForecastSettings: Hashable, Sendable {
    let workdayStartHour: Int
    let workdayEndHour: Int
    /// Meetings separated by less than this count as back-to-back.
    let backToBackGap: TimeInterval = 10 * 60
    /// The shortest free stretch worth calling a clearing.
    let minimumClearing: TimeInterval = 30 * 60

    init(workdayStartHour: Int = 9, workdayEndHour: Int = 18) {
        let start = min(max(workdayStartHour, 0), 23)
        self.workdayStartHour = start
        self.workdayEndHour = min(max(workdayEndHour, start + 1), 24)
    }
}

struct HourForecast: Identifiable, Hashable, Sendable {
    let start: Date
    let cover: Double
    let condition: Condition
    var id: Date { start }
}

struct DayForecast: Hashable, Sendable {
    let day: Date
    let workday: DateInterval
    let condition: Condition
    /// Share of the workday spent in meetings, 0...1. Forecast's "cloud cover".
    let cover: Double
    let meetingCount: Int
    let longestStreak: Int
    let isDoubleBooked: Bool
    let hours: [HourForecast]
    /// Merged busy time inside the workday, sorted.
    let busy: [BusyInterval]

    func isBusy(at date: Date) -> Bool {
        busy.contains { $0.start <= date && date < $0.end }
    }

    /// Start of the next free stretch of at least `minimum`, at or after `now`.
    func nextClearing(after now: Date, minimum: TimeInterval) -> Date? {
        var cursor = max(now, workday.start)
        guard cursor < workday.end else { return nil }
        for block in busy where block.end > cursor {
            if block.start.timeIntervalSince(cursor) >= minimum { return cursor }
            cursor = max(cursor, block.end)
        }
        return workday.end.timeIntervalSince(cursor) >= minimum ? cursor : nil
    }

    /// Start of the next meeting at or after `now`.
    func nextMeeting(after now: Date) -> Date? {
        busy.first { $0.start >= now }?.start
    }
}

enum ForecastEngine {
    /// How far ahead the widget and app look: today plus the outlook days.
    static func fetchWindow(from date: Date, outlookDays: Int = 5, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: outlookDays + 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    static func forecast(
        for date: Date,
        intervals: [BusyInterval],
        settings: ForecastSettings = ForecastSettings(),
        calendar: Calendar = .current
    ) -> DayForecast {
        let day = calendar.startOfDay(for: date)
        let workday = workdayWindow(on: day, settings: settings, calendar: calendar)

        // The same meeting on two calendars is one meeting.
        let events = Set(intervals.compactMap { $0.clipped(to: workday) })
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        let merged = merge(events)
        let streaks = streaks(in: events, gap: settings.backToBackGap)
        let conflicts = conflicts(in: events)

        let busySeconds = merged.reduce(0) { $0 + $1.duration }
        let cover = workday.duration > 0 ? min(busySeconds / workday.duration, 1) : 0
        let longestStreak = streaks.map(\.count).max() ?? 0
        let stormFronts = streaks.filter { $0.count >= 3 }.compactMap(span)

        return DayForecast(
            day: day,
            workday: workday,
            condition: dayCondition(cover: cover, longestStreak: longestStreak, isDoubleBooked: !conflicts.isEmpty),
            cover: cover,
            meetingCount: events.count,
            longestStreak: longestStreak,
            isDoubleBooked: !conflicts.isEmpty,
            hours: hourly(workday: workday, merged: merged, stormy: stormFronts + conflicts, calendar: calendar),
            busy: merged
        )
    }

    /// Forecasts for the days after `date`.
    static func outlook(
        after date: Date,
        days: Int,
        intervals: [BusyInterval],
        settings: ForecastSettings = ForecastSettings(),
        calendar: Calendar = .current
    ) -> [DayForecast] {
        let today = calendar.startOfDay(for: date)
        return (1...max(days, 1)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today).map {
                forecast(for: $0, intervals: intervals, settings: settings, calendar: calendar)
            }
        }
    }

    // MARK: - Rules

    static func dayCondition(cover: Double, longestStreak: Int, isDoubleBooked: Bool) -> Condition {
        if cover <= 0 { return .clear }
        if longestStreak >= 3 || cover >= 0.75 || isDoubleBooked { return .storm }
        if cover >= 0.5 { return .rain }
        if cover >= 0.25 { return .cloudy }
        return .partlyCloudy
    }

    static func hourCondition(cover: Double, isStormy: Bool) -> Condition {
        if cover <= 0 { return .clear }
        if isStormy { return .storm }
        if cover >= 0.75 { return .rain }
        if cover >= 0.4 { return .cloudy }
        return .partlyCloudy
    }

    // MARK: - Helpers

    static func workdayWindow(on day: Date, settings: ForecastSettings, calendar: Calendar) -> DateInterval {
        let start = calendar.date(byAdding: .hour, value: settings.workdayStartHour, to: day) ?? day
        let end = calendar.date(byAdding: .hour, value: settings.workdayEndHour, to: day) ?? start
        return DateInterval(start: start, end: max(start, end))
    }

    /// Combines overlapping intervals. Input must be sorted by start.
    static func merge(_ sorted: [BusyInterval]) -> [BusyInterval] {
        var result: [BusyInterval] = []
        for interval in sorted {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = BusyInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                result.append(interval)
            }
        }
        return result
    }

    /// Groups meetings that follow each other with less than `gap` in between. Input must be sorted.
    static func streaks(in sorted: [BusyInterval], gap: TimeInterval) -> [[BusyInterval]] {
        var result: [[BusyInterval]] = []
        var streakEnd = Date.distantPast
        for interval in sorted {
            if !result.isEmpty, interval.start.timeIntervalSince(streakEnd) < gap {
                result[result.count - 1].append(interval)
                streakEnd = max(streakEnd, interval.end)
            } else {
                result.append([interval])
                streakEnd = interval.end
            }
        }
        return result
    }

    /// The stretches where two meetings overlap. Input must be sorted.
    static func conflicts(in sorted: [BusyInterval]) -> [BusyInterval] {
        var result: [BusyInterval] = []
        var latestEnd = Date.distantPast
        for interval in sorted {
            if interval.start < latestEnd {
                result.append(BusyInterval(start: interval.start, end: min(interval.end, latestEnd)))
            }
            latestEnd = max(latestEnd, interval.end)
        }
        return result
    }

    private static func span(_ streak: [BusyInterval]) -> BusyInterval? {
        guard let first = streak.first else { return nil }
        return BusyInterval(start: first.start, end: streak.map(\.end).max() ?? first.end)
    }

    private static func hourly(
        workday: DateInterval,
        merged: [BusyInterval],
        stormy: [BusyInterval],
        calendar: Calendar
    ) -> [HourForecast] {
        var hours: [HourForecast] = []
        var cursor = workday.start
        while cursor < workday.end {
            let next = min(calendar.date(byAdding: .hour, value: 1, to: cursor) ?? workday.end, workday.end)
            guard next > cursor else { break } // Never loop forever on an odd calendar or clock change.
            let slot = DateInterval(start: cursor, end: next)
            let busy = merged.compactMap { $0.clipped(to: slot) }.reduce(0) { $0 + $1.duration }
            let cover = slot.duration > 0 ? busy / slot.duration : 0
            let isStormy = stormy.contains { $0.overlaps(slot) }
            hours.append(HourForecast(start: cursor, cover: cover, condition: hourCondition(cover: cover, isStormy: isStormy)))
            cursor = next
        }
        return hours
    }
}

/// A made-up day used for widget gallery previews, so the gallery never shows real calendar data.
enum SampleCalendar {
    static func intervals(around date: Date, calendar: Calendar = .current) -> [BusyInterval] {
        let day = calendar.startOfDay(for: date)
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(byAdding: .minute, value: hour * 60 + minute, to: day) ?? day
        }
        func plusDays(_ days: Int, _ interval: BusyInterval) -> BusyInterval {
            BusyInterval(
                start: calendar.date(byAdding: .day, value: days, to: interval.start) ?? interval.start,
                end: calendar.date(byAdding: .day, value: days, to: interval.end) ?? interval.end
            )
        }
        let today = [
            BusyInterval(start: at(9, 30), end: at(10)),
            BusyInterval(start: at(10), end: at(10, 45)),
            BusyInterval(start: at(10, 50), end: at(11, 30)),
            BusyInterval(start: at(11, 30), end: at(12)),
            BusyInterval(start: at(14), end: at(14, 30)),
        ]
        return today
            + [BusyInterval(start: at(11), end: at(11, 30))].map { plusDays(1, $0) }
            + [BusyInterval(start: at(9), end: at(12)), BusyInterval(start: at(13), end: at(16))].map { plusDays(2, $0) }
            + [BusyInterval(start: at(10), end: at(11)), BusyInterval(start: at(15), end: at(17))].map { plusDays(3, $0) }
            + [BusyInterval(start: at(9), end: at(13)), BusyInterval(start: at(13), end: at(17))].map { plusDays(4, $0) }
    }
}
