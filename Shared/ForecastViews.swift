import SwiftUI
import WidgetKit

enum ForecastLayout {
    case small, medium, large
}

/// One forecast, laid out for a widget size. Used by the widget and by the app's preview.
struct ForecastCard: View {
    let layout: ForecastLayout
    let today: DayForecast
    let outlook: [DayForecast]
    let now: Date
    let season: Season
    var minimumClearing: TimeInterval = ForecastSettings().minimumClearing

    private var theme: Theme { season.theme }

    var body: some View {
        switch layout {
        case .small:
            TodaySummary(today: today, now: now, season: season, minimumClearing: minimumClearing, style: .stacked)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .medium:
            VStack(alignment: .leading, spacing: 0) {
                TodaySummary(today: today, now: now, season: season, minimumClearing: minimumClearing, style: .inline)
                Spacer(minLength: 12)
                HourlyStrip(hours: today.hours, now: now, season: season, limit: 5)
            }
        case .large:
            VStack(alignment: .leading, spacing: 0) {
                TodaySummary(today: today, now: now, season: season, minimumClearing: minimumClearing, style: .inline)
                Text(ForecastText.headline(for: today, now: now, season: season))
                    .font(.inter(13))
                    .foregroundStyle(theme.secondaryInk)
                    .lineLimit(2)
                    .padding(.top, 14)
                HourlyStrip(hours: today.hours, now: now, season: season, limit: 5)
                    .padding(.top, 20)
                OutlookList(days: Array(outlook.prefix(5)), season: season, now: now)
                    .padding(.top, 28)
                Spacer(minLength: 0)
            }
        }
    }
}

struct TodaySummary: View {
    enum Style { case stacked, inline }

    let today: DayForecast
    let now: Date
    let season: Season
    let minimumClearing: TimeInterval
    let style: Style

    private var theme: Theme { season.theme }

    var body: some View {
        switch style {
        case .stacked:
            VStack(alignment: .leading, spacing: 0) {
                ConditionIcon(condition: today.condition, season: season, size: 26)
                Spacer(minLength: 0)
                coverReading(size: 34)
                conditionLabel
                    .padding(.top, 2)
                outlookLine
                    .padding(.top, 3)
            }
        case .inline:
            HStack(alignment: .center, spacing: 14) {
                ConditionIcon(condition: today.condition, season: season, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        coverReading(size: 28)
                        conditionLabel
                    }
                    outlookLine
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func coverReading(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(ForecastText.percent(today.cover))
                .font(.inter(size, .light))
                .tracking(-size * 0.03)
                .monospacedDigit()
                .foregroundStyle(theme.ink)
            Text("cover")
                .font(.inter(11))
                .foregroundStyle(theme.secondaryInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ForecastText.percent(today.cover)) of the workday in meetings")
    }

    private var conditionLabel: some View {
        Text(today.condition.label(for: season))
            .font(.inter(13, .medium))
            .foregroundStyle(theme.ink)
            .lineLimit(1)
    }

    private var outlookLine: some View {
        Text(ForecastText.outlookLine(for: today, now: now, minimumClearing: minimumClearing))
            .font(.inter(11))
            .foregroundStyle(theme.secondaryInk)
            .lineLimit(1)
    }
}

struct ConditionIcon: View {
    let condition: Condition
    let season: Season
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: condition.symbol(for: season))
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: size, weight: .light))
            .foregroundStyle(season.theme.accent)
            .frame(width: size * 1.25, height: size * 1.1)
            .widgetAccentable()
            .accessibilityLabel(condition.label(for: season))
    }
}

struct HourlyStrip: View {
    let hours: [HourForecast]
    let now: Date
    let season: Season
    let limit: Int

    private var theme: Theme { season.theme }

    /// The hours from now on, or the whole workday if it hasn't started or is already over.
    private var visible: [HourForecast] {
        let upcoming = hours.filter { $0.start.addingTimeInterval(3600) > now }
        return Array((upcoming.isEmpty ? hours : upcoming).prefix(limit))
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visible) { hour in
                let isNow = hour.start <= now && now < hour.start.addingTimeInterval(3600)
                VStack(spacing: 8) {
                    Text(isNow ? "Now" : ForecastText.hour(hour.start))
                        .font(.inter(10, isNow ? .medium : .regular))
                        .foregroundStyle(isNow ? theme.ink : theme.secondaryInk)
                        .lineLimit(1)
                    ConditionIcon(condition: hour.condition, season: season, size: 15)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct OutlookList: View {
    let days: [DayForecast]
    let season: Season
    let now: Date

    private var theme: Theme { season.theme }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(days, id: \.day) { day in
                HStack(spacing: 12) {
                    Text(day.day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.inter(12))
                        .foregroundStyle(theme.ink)
                        .frame(width: 40, alignment: .leading)
                    ConditionIcon(condition: day.condition, season: season, size: 15)
                    CoverBar(cover: day.cover, season: season)
                        .frame(height: 3)
                    Text(ForecastText.percent(day.cover))
                        .font(.inter(11))
                        .monospacedDigit()
                        .foregroundStyle(theme.secondaryInk)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }
}

struct CoverBar: View {
    let cover: Double
    let season: Season

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(season.theme.ink.opacity(0.06))
                Capsule()
                    .fill(season.theme.accent.opacity(0.7))
                    .frame(width: proxy.size.width * min(max(cover, 0), 1))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Seasonal dressing

struct SeasonBackground: View {
    let season: Season

    var body: some View {
        LinearGradient(
            colors: [season.theme.backgroundTop, season.theme.backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// A small cluster of seasonal motifs (blossoms, beach, pumpkins, snow) for the season picker.
struct SeasonDecor: View {
    let season: Season
    var scale: CGFloat = 1

    var body: some View {
        HStack(alignment: .bottom, spacing: 4 * scale) {
            ForEach(Array(season.theme.decor.enumerated()), id: \.offset) { _, item in
                switch item {
                case let .symbol(name, color, size, angle):
                    Image(systemName: name)
                        .font(.system(size: size * scale))
                        .foregroundStyle(color)
                        .rotationEffect(.degrees(angle))
                case let .pumpkin(size, angle):
                    Pumpkin()
                        .frame(width: size * scale, height: size * scale)
                        .rotationEffect(.degrees(angle))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// SF Symbols has no pumpkin, so here is one.
struct Pumpkin: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let skin = Color(light: 0xE59A63, dark: 0xEBA574)
            let shade = Color(light: 0xD8814A, dark: 0xE08E5C)
            ZStack {
                Ellipse().fill(shade).frame(width: w * 0.52, height: h * 0.7).offset(x: -w * 0.2, y: h * 0.12)
                Ellipse().fill(shade).frame(width: w * 0.52, height: h * 0.7).offset(x: w * 0.2, y: h * 0.12)
                Ellipse().fill(skin).frame(width: w * 0.5, height: h * 0.76).offset(y: h * 0.1)
                Capsule()
                    .fill(Color(light: 0x8FA06A, dark: 0x9DAE78))
                    .frame(width: w * 0.11, height: h * 0.24)
                    .rotationEffect(.degrees(14))
                    .offset(x: w * 0.02, y: -h * 0.34)
            }
            .frame(width: w, height: h)
        }
    }
}
