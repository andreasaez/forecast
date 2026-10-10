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
        let store = EKEventStore()
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        // Keep the store alive until macOS has answered, or the answer can be lost.
        withExtendedLifetime(store) {}
        return granted
    }

    /// - Parameter countingBreaksAsFree: When on, each title is passed to `BreakMatcher.isBreak`
    ///   for a yes/no answer and is not kept anywhere. When off, titles are not read at all.
    func busyIntervals(in window: DateInterval, countingBreaksAsFree: Bool = false) -> [BusyInterval] {
        guard Self.access == .granted else { return [] }
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        return store.events(matching: predicate).compactMap { event in
            Self.busyInterval(
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                isFree: event.availability == .free,
                isCancelled: event.status == .canceled,
                // `&&` short-circuits: with the setting off, the title is never read.
                isBreak: countingBreaksAsFree && BreakMatcher.isBreak(event.title)
            )
        }
    }

    /// Which events count as busy time. Kept free of EventKit types so tests can cover it, including events
    /// with no start or end (EventKit declares those as never missing, but a corrupt event can lack them).
    static func busyInterval(start: Date?, end: Date?, isAllDay: Bool, isFree: Bool, isCancelled: Bool, isBreak: Bool) -> BusyInterval? {
        guard let start, let end, !isAllDay, !isFree, !isCancelled, !isBreak else { return nil }
        return BusyInterval(start: start, end: end)
    }
}
