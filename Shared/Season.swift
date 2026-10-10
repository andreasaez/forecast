import AppKit
import SwiftUI

enum Season: String, CaseIterable, Identifiable, Sendable {
    case spring, summer, autumn, winter

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    /// Picks the meteorological season for `date`, flipped for the southern hemisphere.
    /// The hemisphere is guessed from the Mac's time zone setting, so no location access is needed.
    static func current(on date: Date = .now, calendar: Calendar = .current, timeZone: TimeZone = .current) -> Season {
        let month = calendar.component(.month, from: date)
        let northern: Season = switch month {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .autumn
        default: .winter
        }
        guard isSouthern(timeZone) else { return northern }
        switch northern {
        case .spring: return .autumn
        case .summer: return .winter
        case .autumn: return .spring
        case .winter: return .summer
        }
    }

    private static func isSouthern(_ timeZone: TimeZone) -> Bool {
        let southern = [
            "Australia/", "Antarctica/", "Pacific/Auckland", "Pacific/Chatham", "Pacific/Fiji",
            "America/Argentina", "America/Buenos_Aires", "America/Sao_Paulo", "America/Santiago",
            "America/Montevideo", "America/Asuncion", "America/La_Paz", "America/Lima",
            "Africa/Johannesburg", "Africa/Maputo", "Africa/Windhoek", "Africa/Harare",
            "Indian/Mauritius", "Indian/Reunion", "Atlantic/Stanley",
        ]
        return southern.contains { timeZone.identifier.hasPrefix($0) }
    }
}

// MARK: - Palette

struct Theme {
    let backgroundTop: Color
    let backgroundBottom: Color
    let ink: Color
    let secondaryInk: Color
    let accent: Color
    let decor: [Decoration]
}

enum Decoration: Hashable {
    case symbol(String, Color, size: CGFloat, angle: Double)
    case pumpkin(size: CGFloat, angle: Double)
}

extension Season {
    /// Near-white in light mode, quiet graphite in dark mode. The season lives in the accent.
    var theme: Theme {
        switch self {
        case .spring:
            let blossom = Color(light: 0xD98CA4, dark: 0xE6A6BA)
            return Theme(
                backgroundTop: Color(light: 0xFCFDFB, dark: 0x1C1D1C),
                backgroundBottom: Color(light: 0xF4F7F1, dark: 0x202220),
                ink: Color(light: 0x1F2420, dark: 0xEDEFEC),
                secondaryInk: Color(light: 0x7D857A, dark: 0x9BA098),
                accent: blossom,
                decor: [
                    .symbol("camera.macro", blossom, size: 16, angle: -8),
                    .symbol("leaf.fill", Color(light: 0x9DBB8C, dark: 0xA8C698), size: 11, angle: 30),
                ]
            )
        case .summer:
            let sun = Color(light: 0xE8A23D, dark: 0xF0B65E)
            return Theme(
                backgroundTop: Color(light: 0xFFFEFA, dark: 0x1D1C1A),
                backgroundBottom: Color(light: 0xFBF7EE, dark: 0x22201D),
                ink: Color(light: 0x24211C, dark: 0xF0EEEA),
                secondaryInk: Color(light: 0x878072, dark: 0xA19B91),
                accent: sun,
                decor: [
                    .symbol("beach.umbrella.fill", sun, size: 16, angle: -10),
                    .symbol("water.waves", Color(light: 0x7FBDB8, dark: 0x8CCAC5), size: 11, angle: 0),
                ]
            )
        case .autumn:
            return Theme(
                backgroundTop: Color(light: 0xFFFDFB, dark: 0x1C1C1B),
                backgroundBottom: Color(light: 0xF9F5F0, dark: 0x21201F),
                ink: Color(light: 0x26221F, dark: 0xF0EDEA),
                secondaryInk: Color(light: 0x8A817A, dark: 0xA29C97),
                accent: Color(light: 0xD8814A, dark: 0xE8955F),
                decor: [
                    .pumpkin(size: 17, angle: 0),
                    .symbol("leaf.fill", Color(light: 0xE0A35C, dark: 0xE9B271), size: 11, angle: -35),
                ]
            )
        case .winter:
            let frost = Color(light: 0x7AA3C9, dark: 0x96BADD)
            return Theme(
                backgroundTop: Color(light: 0xFCFDFE, dark: 0x1B1C1E),
                backgroundBottom: Color(light: 0xF3F6F9, dark: 0x1F2124),
                ink: Color(light: 0x1E2329, dark: 0xECEFF2),
                secondaryInk: Color(light: 0x7C8691, dark: 0x989FA7),
                accent: frost,
                decor: [
                    .symbol("snowflake", frost, size: 16, angle: 0),
                    .symbol("snowflake", frost, size: 10, angle: 20),
                ]
            )
        }
    }
}

// MARK: - Weather vocabulary

extension Condition {
    func symbol(for season: Season) -> String {
        switch (self, season) {
        case (.clear, _): "sun.max.fill"
        case (.partlyCloudy, _): "cloud.sun.fill"
        case (.cloudy, .autumn): "wind"
        case (.cloudy, _): "cloud.fill"
        case (.rain, .winter): "cloud.snow.fill"
        case (.rain, .autumn): "cloud.drizzle.fill"
        case (.rain, _): "cloud.rain.fill"
        case (.storm, .winter): "wind.snow"
        case (.storm, _): "cloud.bolt.rain.fill"
        }
    }

    func label(for season: Season) -> String {
        switch (self, season) {
        case (.clear, .spring): "Clear skies"
        case (.clear, .summer): "Sunshine"
        case (.clear, .autumn): "Crisp & clear"
        case (.clear, .winter): "Bright & cold"
        case (.partlyCloudy, _): "Partly cloudy"
        case (.cloudy, .autumn): "Breezy"
        case (.cloudy, _): "Overcast"
        case (.rain, .winter): "Snow"
        case (.rain, .autumn): "Drizzle"
        case (.rain, _): "Showers"
        case (.storm, .winter): "Blizzard"
        case (.storm, _): "Thunderstorms"
        }
    }
}

// MARK: - Colour helper

extension Color {
    /// A colour that follows the system's light or dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
