import Foundation

/// The only calendar data Forecast ever holds: when something starts and when it ends.
///
/// This type is the privacy boundary. `CalendarReader` turns each event into a
/// `BusyInterval` straight away and lets the event go. Titles, notes, locations,
/// attendees, URLs and calendar names are never read, copied, stored or logged.
struct BusyInterval: Hashable, Sendable {
    let start: Date
    let end: Date

    init(start: Date, end: Date) {
        self.start = start
        self.end = max(start, end)
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    func clipped(to window: DateInterval) -> BusyInterval? {
        let clippedStart = max(start, window.start)
        let clippedEnd = min(end, window.end)
        return clippedStart < clippedEnd ? BusyInterval(start: clippedStart, end: clippedEnd) : nil
    }

    func overlaps(_ window: DateInterval) -> Bool {
        start < window.end && end > window.start
    }
}
