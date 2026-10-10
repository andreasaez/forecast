import EventKit

/// The one place Forecast touches EventKit.
///
/// `scripts/privacy-audit.sh` enforces that this is the only file importing EventKit,
/// that it reads nothing from an event except `startDate`, `endDate`, `isAllDay`,
/// `availability` and `status` (plus `title`, only as input to the opt-in break check),
/// and that it never writes to the calendar.
final class CalendarReader {
    enum Access: Equatable {
        case granted, notDetermined, denied
    }

    /// Posted when the user's calendar changes. Carries no event data.
    static let didChange = Notification.Name.EKEventStoreChanged

    private let store = EKEventStore()

    static var access: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Reading event times requires full access; EventKit offers no times-only permission.
    /// Permission covers the whole app, so a short-lived store is enough to ask.
    static func requestAccess() async -> Bool {
        (try? await EKEventStore().requestFullAccessToEvents()) ?? false
    }

    /// - Parameter countingBreaksAsFree: When on, each title is passed to `BreakMatcher.isBreak`
    ///   for a yes/no answer and is not kept anywhere. When off, titles are not read at all.
    func busyIntervals(in window: DateInterval, countingBreaksAsFree: Bool = false) -> [BusyInterval] {
        guard Self.access == .granted else { return [] }
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        return store.events(matching: predicate).compactMap { event in
            guard !event.isAllDay, event.availability != .free, event.status != .canceled else { return nil }
            if countingBreaksAsFree, BreakMatcher.isBreak(event.title) { return nil }
            return BusyInterval(start: event.startDate, end: event.endDate)
        }
    }
}
