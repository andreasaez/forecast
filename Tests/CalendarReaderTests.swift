import Foundation
import Testing

struct CalendarReaderTests {
    let start = Date(timeIntervalSince1970: 1_791_000_000)
    var end: Date { start.addingTimeInterval(1_800) }

    func interval(start: Date?, end: Date?, isAllDay: Bool = false, isFree: Bool = false,
                  isCancelled: Bool = false, isBreak: Bool = false) -> BusyInterval? {
        CalendarReader.busyInterval(start: start, end: end, isAllDay: isAllDay, isFree: isFree,
                                    isCancelled: isCancelled, isBreak: isBreak)
    }

    @Test func anOrdinaryMeetingCounts() {
        #expect(interval(start: start, end: end) == BusyInterval(start: start, end: end))
    }

    @Test func eventsWithNoStartOrEndAreSkippedInsteadOfCrashing() {
        #expect(interval(start: nil, end: end) == nil)
        #expect(interval(start: start, end: nil) == nil)
        #expect(interval(start: nil, end: nil) == nil)
    }

    @Test func allDayFreeCancelledAndBreakEventsDontCount() {
        #expect(interval(start: start, end: end, isAllDay: true) == nil)
        #expect(interval(start: start, end: end, isFree: true) == nil)
        #expect(interval(start: start, end: end, isCancelled: true) == nil)
        #expect(interval(start: start, end: end, isBreak: true) == nil)
    }
}
