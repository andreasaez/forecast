import Foundation

/// The words Forecast shows. Built only from times and counts, never from event details.
enum ForecastText {
    static func dayLabel(for forecast: DayForecast, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(forecast.day, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           calendar.isDate(forecast.day, inSameDayAs: tomorrow) { return "Tomorrow" }
        return forecast.day.formatted(.dateTime.weekday(.wide))
    }

    static func headline(for today: DayForecast, now: Date, season: Season) -> String {
        if now >= today.workday.end { return "The skies have cleared for today." }
        switch today.condition {
        case .clear:
            return "Not a cloud in sight."
        case .partlyCloudy:
            return "Mostly bright, with a few passing meetings."
        case .cloudy:
            return "Overcast, with breaks in between."
        case .rain:
            return season == .winter ? "A steady snowfall of meetings." : "Steady meetings. Bring an umbrella."
        case .storm:
            if today.longestStreak >= 3 { return "\(today.longestStreak) back-to-back. Storm warning." }
            if today.isDoubleBooked { return "Clashing fronts: you're double-booked." }
            return "A heavy front of meetings moving through."
        }
    }

    static func outlookLine(for today: DayForecast, now: Date, minimumClearing: TimeInterval) -> String {
        if now >= today.workday.end { return "Workday over" }
        if today.busy.isEmpty { return "Clear all day" }
        if today.isBusy(at: now) {
            guard let clearing = today.nextClearing(after: now, minimum: minimumClearing) else { return "No clearing today" }
            return "Clears at \(time(clearing))"
        }
        if now < today.workday.start, let first = today.nextMeeting(after: now) {
            return "First cloud at \(time(first))"
        }
        if let next = today.nextMeeting(after: now) { return "Clear until \(time(next))" }
        return "Clear from here"
    }

    static func percent(_ cover: Double) -> String {
        "\(Int((cover * 100).rounded()))%"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func hour(_ date: Date) -> String {
        date.formatted(.dateTime.hour())
    }
}
