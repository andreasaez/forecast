import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: ForecastModel
    @AppStorage("season") private var seasonName = Season.current().rawValue
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    private var season: Binding<Season> {
        Binding(
            get: { Season(rawValue: seasonName) ?? .current() },
            set: { seasonName = $0.rawValue }
        )
    }

    var body: some View {
        Group {
            if hasOnboarded && model.access == .granted {
                HomeView(season: season)
            } else {
                OnboardingView(season: season.wrappedValue) { hasOnboarded = true }
            }
        }
        .frame(width: 620)
        .background {
            if hasOnboarded && model.access == .granted {
                SeasonBackground(season: season.wrappedValue)
            } else {
                GlassBackdrop(season: season.wrappedValue)
            }
        }
        .foregroundStyle(season.wrappedValue.theme.ink)
        .animation(.easeInOut(duration: 0.25), value: seasonName)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject private var model: ForecastModel
    let season: Season
    let onContinue: () -> Void

    private var theme: Theme { season.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ConditionIcon(condition: .clear, season: season, size: 30)

            VStack(alignment: .leading, spacing: 8) {
                Text("Forecast")
                    .font(.inter(32, .semibold))
                    .tracking(-0.8)
                Text("Your calendar as the weather.")
                    .font(.inter(15))
                    .foregroundStyle(theme.secondaryInk)
            }
            .padding(.top, 28)

            Text("Forecast reads your calendar and provides a view of what to expect for the day.")
                .font(.inter(19))
                .tracking(-0.2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 28)

            VStack(alignment: .leading, spacing: 20) {
                Promise(symbol: "wifi.slash", title: "No internet access",
                        detail: "The app is sandboxed with no network permission. It can’t send anything anywhere.", theme: theme)
                Promise(symbol: "clock", title: "Only what it needs",
                        detail: "Meeting times, plus a quick check for breaks like Lunch or Gym. Personal details are never kept.", theme: theme)
                Promise(symbol: "tray", title: "Nothing kept",
                        detail: "No database, no logs, no analytics. The weather is worked out fresh each time.", theme: theme)
                Promise(symbol: "chevron.left.forwardslash.chevron.right", title: "Open source",
                        detail: "100% open source, play and modify as your own.", theme: theme)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 20)
            .padding(.top, 36)

            action
                .padding(.top, 32)
        }
        .padding(.horizontal, 52)
        .padding(.vertical, 48)
    }

    @ViewBuilder
    private var action: some View {
        switch model.access {
        case .notDetermined:
            primaryButton("Allow calendar access") {
                Task {
                    await model.requestAccess()
                    if model.access == .granted { onContinue() }
                }
            }
        case .denied:
            VStack(alignment: .leading, spacing: 10) {
                Text("Calendar access is off. Turn on Forecast in System Settings › Privacy & Security › Calendars.")
                    .font(.inter(13))
                    .foregroundStyle(theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                primaryButton("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        case .granted:
            primaryButton("Continue", action: onContinue)
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.inter(13, .medium))
                .padding(.horizontal, 10)
        }
        .glassProminentButton()
        .tint(theme.accent)
        .controlSize(.large)
    }
}

// MARK: - Glass

/// The desktop, blurred through the window, washed with the season's colours.
struct GlassBackdrop: View {
    let season: Season

    var body: some View {
        ZStack {
            BehindWindowBlur()
            LinearGradient(
                colors: [season.theme.backgroundTop.opacity(0.35), season.theme.backgroundBottom.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private extension View {
    /// Liquid Glass on macOS 26, frosted material before that.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.25)))
        }
    }

    @ViewBuilder
    func glassProminentButton() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}

private struct Promise: View {
    let symbol: String
    let title: String
    let detail: String
    let theme: Theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(theme.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.inter(13, .medium))
                Text(detail)
                    .font(.inter(13))
                    .lineSpacing(2)
                    .foregroundStyle(theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject private var model: ForecastModel
    @Binding var season: Season

    private var theme: Theme { season.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Forecast")
                    .font(.inter(13, .medium))
                    .foregroundStyle(theme.secondaryInk)
                Text(ForecastText.headline(for: model.today, now: model.now, season: season))
                    .font(.inter(24))
                    .tracking(-0.4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SeasonPicker(selection: $season)

            Toggle(isOn: $model.countBreaksAsFree) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Count breaks as free time")
                        .font(.inter(14, .semibold))
                    Text("Lunch, gym, a walk, walking the dog: time you block out for yourself stays sunny. Titles are checked on your Mac and never kept.")
                        .font(.inter(12))
                        .foregroundStyle(theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .tint(theme.accent)

            HStack(alignment: .top, spacing: 16) {
                preview(.small, width: 170)
                preview(.medium, width: 364)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Add it to your desktop")
                    .font(.inter(14, .semibold))
                Text("Right-click the desktop, choose Edit Widgets, and search for Forecast. Right-click a widget and choose Edit “Forecast” to pick its season, working hours and whether breaks count as free time.")
                    .font(.inter(13))
                    .foregroundStyle(theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Image(systemName: "lock.fill").foregroundStyle(theme.accent)
                Text("Forecast reads your calendar and provides a view of what to expect for the day. No network access.")
                    .foregroundStyle(theme.secondaryInk)
            }
            .font(.inter(12))
        }
        .padding(40)
    }

    private func preview(_ layout: ForecastLayout, width: CGFloat) -> some View {
        ForecastCard(
            layout: layout,
            today: model.today,
            outlook: model.outlook,
            now: model.now,
            season: season,
            minimumClearing: model.settings.minimumClearing
        )
        .padding(16)
        .frame(width: width, height: 170)
        .background(SeasonBackground(season: season))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(theme.ink.opacity(0.08)))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}

struct SeasonPicker: View {
    @Binding var selection: Season

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Season.allCases) { season in
                let isSelected = season == selection
                Button { selection = season } label: {
                    VStack(spacing: 8) {
                        SeasonDecor(season: season, scale: 0.9)
                            .frame(height: 26)
                        Text(season.name)
                            .font(.inter(12, isSelected ? .semibold : .regular))
                            .foregroundStyle(season.theme.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(colors: [season.theme.backgroundTop, season.theme.backgroundBottom],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? season.theme.accent : season.theme.ink.opacity(0.08),
                                          lineWidth: isSelected ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(season.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
