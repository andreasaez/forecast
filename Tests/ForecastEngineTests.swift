import Foundation
import Testing

struct ForecastEngineTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    var day: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))! }

    func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        calendar.date(byAdding: .minute, value: (dayOffset * 24 + hour) * 60 + minute, to: day)!
    }

    func meeting(_ startHour: Int, _ startMinute: Int, _ endHour: Int, _ endMinute: Int) -> BusyInterval {
        BusyInterval(start: at(startHour, startMinute), end: at(endHour, endMinute))
    }

    func forecast(_ intervals: [BusyInterval], settings: ForecastSettings = ForecastSettings()) -> DayForecast {
        ForecastEngine.forecast(for: at(8), intervals: intervals, settings: settings, calendar: calendar)
    }

    @Test func emptyDayIsSunshine() {
        let result = forecast([])
        #expect(result.condition == .clear)
        #expect(result.cover == 0)
        #expect(result.hours.allSatisfy { $0.condition == .clear })
    }

    @Test func threeBackToBackMeetingsMakeAThunderstorm() {
        let result = forecast([meeting(10, 0, 10, 30), meeting(10, 30, 11, 0), meeting(11, 5, 11, 30)])
        #expect(result.longestStreak == 3)
        #expect(result.condition == .storm)
        #expect(result.hours.first { $0.start == at(10) }?.condition == .storm)
    }

    @Test func emptyAfternoonStaysSunnyAfterAStormyMorning() {
        let result = forecast([meeting(9, 0, 10, 0), meeting(10, 0, 11, 0), meeting(11, 0, 12, 0)])
        let afternoon = result.hours.filter { $0.start >= at(13) }
        #expect(!afternoon.isEmpty)
        #expect(afternoon.allSatisfy { $0.condition == .clear })
    }

    @Test func aTenMinuteGapBreaksAStreak() {
        let result = forecast([meeting(10, 0, 10, 30), meeting(10, 40, 11, 0), meeting(11, 10, 11, 30)])
        #expect(result.longestStreak == 1)
        #expect(result.condition != .storm)
    }

    @Test func doubleBookingIsStormy() {
        let result = forecast([meeting(14, 0, 15, 0), meeting(14, 30, 15, 30)])
        #expect(result.isDoubleBooked)
        #expect(result.condition == .storm)
    }

    @Test func theSameMeetingOnTwoCalendarsCountsOnce() {
        let result = forecast([meeting(14, 0, 15, 0), meeting(14, 0, 15, 0)])
        #expect(result.meetingCount == 1)
        #expect(!result.isDoubleBooked)
    }

    @Test func coverIsTheShareOfTheWorkdayInMeetings() {
        // 3 of 9 workday hours, spread out so nothing is back-to-back.
        let result = forecast([meeting(9, 0, 10, 0), meeting(12, 0, 13, 0), meeting(15, 0, 16, 0)])
        #expect(abs(result.cover - 1.0 / 3.0) < 0.0001)
        #expect(result.condition == .cloudy)
    }

    @Test func meetingsOutsideTheWorkdayAreIgnored() {
        let result = forecast([meeting(6, 0, 7, 0), meeting(19, 0, 21, 0)])
        #expect(result.condition == .clear)
        #expect(result.meetingCount == 0)
    }

    @Test func meetingsOnOtherDaysAreIgnored() {
        let tomorrow = BusyInterval(start: at(10, dayOffset: 1), end: at(11, dayOffset: 1))
        #expect(forecast([tomorrow]).condition == .clear)
    }

    @Test func hourlyStripCoversTheWorkday() {
        let result = forecast([], settings: ForecastSettings(workdayStartHour: 8, workdayEndHour: 17))
        #expect(result.hours.count == 9)
        #expect(result.hours.first?.start == at(8))
    }

    @Test func nextClearingSkipsGapsThatAreTooShort() {
        let result = forecast([meeting(10, 0, 11, 0), meeting(11, 15, 12, 0)])
        #expect(result.nextClearing(after: at(10, 30), minimum: 30 * 60) == at(12))
    }

    @Test func nextClearingIsNilWhenTheDayIsFull() {
        let result = forecast([meeting(9, 0, 18, 0)])
        #expect(result.nextClearing(after: at(9), minimum: 30 * 60) == nil)
    }

    @Test func invalidWorkdayHoursAreClamped() {
        let settings = ForecastSettings(workdayStartHour: 20, workdayEndHour: 4)
        #expect(settings.workdayStartHour == 20)
        #expect(settings.workdayEndHour == 21)
        #expect(ForecastSettings(workdayStartHour: -3, workdayEndHour: 99).workdayEndHour == 24)
    }

    @Test func outlookCoversTheFollowingDays() {
        let intervals = [BusyInterval(start: at(9, dayOffset: 1), end: at(18, dayOffset: 1))]
        let outlook = ForecastEngine.outlook(after: at(8), days: 3, intervals: intervals, calendar: calendar)
        #expect(outlook.count == 3)
        #expect(outlook[0].condition == .storm)
        #expect(outlook[1].condition == .clear)
    }

    @Test func seasonFollowsTheHemisphere() {
        let october = at(12)
        #expect(Season.current(on: october, calendar: calendar, timeZone: TimeZone(identifier: "Europe/Dublin")!) == .autumn)
        #expect(Season.current(on: october, calendar: calendar, timeZone: TimeZone(identifier: "Australia/Sydney")!) == .spring)
    }
}
