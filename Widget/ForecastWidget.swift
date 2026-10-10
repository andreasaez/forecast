import AppIntents
import SwiftUI
import WidgetKit

@main
struct ForecastWidgetBundle: WidgetBundle {
    var body: some Widget {
        ForecastWidget()
    }
}

struct ForecastWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Forecast", intent: ForecastConfiguration.self, provider: ForecastProvider()) { entry in
            ForecastWidgetView(entry: entry)
        }
        .configurationDisplayName("Forecast")
        .description("Your calendar as the weather: a view of what to expect for the day.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Configuration

struct ForecastConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Forecast"
    static let description = IntentDescription("Choose a season, your working hours, and whether breaks count as free time.")

    @Parameter(title: "Season", default: .automatic)
    var season: SeasonOption

    @Parameter(title: "Workday starts", default: 9, inclusiveRange: (0, 23))
    var workdayStart: Int

    @Parameter(title: "Workday ends", default: 18, inclusiveRange: (1, 24))
    var workdayEnd: Int

    @Parameter(
        title: "Count breaks as free time",
        description: "Events titled like Lunch, Gym or Walk don't count as meetings. Titles are checked on your Mac and never kept.",
        default: true
    )
    var countBreaksAsFree: Bool

    var settings: ForecastSettings {
        ForecastSettings(workdayStartHour: workdayStart, workdayEndHour: workdayEnd)
    }
}

enum SeasonOption: String, AppEnum {
    case automatic, spring, summer, autumn, winter

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Season"
    static let caseDisplayRepresentations: [SeasonOption: DisplayRepresentation] = [
        .automatic: DisplayRepresentation(title: "Match the date", image: .init(systemName: "calendar")),
        .spring: DisplayRepresentation(title: "Spring", image: .init(systemName: "camera.macro")),
        .summer: DisplayRepresentation(title: "Summer", image: .init(systemName: "beach.umbrella.fill")),
        .autumn: DisplayRepresentation(title: "Autumn", image: .init(systemName: "leaf.fill")),
        .winter: DisplayRepresentation(title: "Winter", image: .init(systemName: "snowflake")),
    ]

    func resolved(on date: Date) -> Season {
        switch self {
        case .automatic: .current(on: date)
        case .spring: .spring
        case .summer: .summer
        case .autumn: .autumn
        case .winter: .winter
        }
    }
}

// MARK: - Timeline

struct ForecastEntry: TimelineEntry {
    enum Content {
        case forecast(today: DayForecast, outlook: [DayForecast])
        case needsAccess
    }

    let date: Date
    let season: Season
    let content: Content
    let minimumClearing: TimeInterval

    static func sample(at date: Date = .now, season: Season = .current()) -> ForecastEntry {
        let intervals = SampleCalendar.intervals(around: date)
        return ForecastEntry(
            date: date,
            season: season,
            content: .forecast(
                today: ForecastEngine.forecast(for: date, intervals: intervals),
                outlook: ForecastEngine.outlook(after: date, days: 5, intervals: intervals)
            ),
            minimumClearing: ForecastSettings().minimumClearing
        )
    }
}

struct ForecastProvider: AppIntentTimelineProvider {
    private static let step: TimeInterval = 15 * 60
    private static let entryCount = 8

    func placeholder(in context: Context) -> ForecastEntry {
        .sample()
    }

    func snapshot(for configuration: ForecastConfiguration, in context: Context) async -> ForecastEntry {
        // The widget gallery shows a made-up day, never the real calendar.
        if context.isPreview { return .sample(season: configuration.season.resolved(on: .now)) }
        return entries(for: configuration, from: .now, count: 1).first ?? .sample()
    }

    func timeline(for configuration: ForecastConfiguration, in context: Context) async -> Timeline<ForecastEntry> {
        let now = Date()
        let entries = entries(for: configuration, from: now, count: Self.entryCount)
        if case .needsAccess = entries.first?.content {
            return Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60)))
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func entries(for configuration: ForecastConfiguration, from start: Date, count: Int) -> [ForecastEntry] {
        let settings = configuration.settings
        guard CalendarReader.access == .granted else {
            return [ForecastEntry(
                date: start,
                season: configuration.season.resolved(on: start),
                content: .needsAccess,
                minimumClearing: settings.minimumClearing
            )]
        }
        let window = ForecastEngine.fetchWindow(from: start, outlookDays: 5)
        let intervals = CalendarReader().busyIntervals(in: window, countingBreaksAsFree: configuration.countBreaksAsFree)
        return (0..<count).map { index in
            let date = start.addingTimeInterval(Double(index) * Self.step)
            return ForecastEntry(
                date: date,
                season: configuration.season.resolved(on: date),
                content: .forecast(
                    today: ForecastEngine.forecast(for: date, intervals: intervals, settings: settings),
                    outlook: ForecastEngine.outlook(after: date, days: 5, intervals: intervals, settings: settings)
                ),
                minimumClearing: settings.minimumClearing
            )
        }
    }
}

// MARK: - Views

struct ForecastWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ForecastEntry

    private var layout: ForecastLayout {
        switch family {
        case .systemSmall: .small
        case .systemLarge, .systemExtraLarge: .large
        default: .medium
        }
    }

    var body: some View {
        Group {
            switch entry.content {
            case let .forecast(today, outlook):
                ForecastCard(
                    layout: layout,
                    today: today,
                    outlook: outlook,
                    now: entry.date,
                    season: entry.season,
                    minimumClearing: entry.minimumClearing
                )
            case .needsAccess:
                NeedsAccessView(season: entry.season)
            }
        }
        .containerBackground(for: .widget) {
            SeasonBackground(season: entry.season)
        }
    }
}

struct NeedsAccessView: View {
    let season: Season

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 26))
                .foregroundStyle(season.theme.accent)
            Spacer(minLength: 0)
            Text("Open Forecast to allow calendar access.")
                .font(.inter(13, .semibold))
                .foregroundStyle(season.theme.ink)
            Text("Nothing leaves your Mac.")
                .font(.inter(11))
                .foregroundStyle(season.theme.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
