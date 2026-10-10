import SwiftUI
import WidgetKit

@main
struct ForecastApp: App {
    @StateObject private var model = ForecastModel()

    var body: some Scene {
        WindowGroup("Forecast") {
            ContentView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

/// Holds today's forecast for the app window. Everything stays in memory; nothing is written to disk.
@MainActor
final class ForecastModel: ObservableObject {
    @Published private(set) var access = CalendarReader.access
    @Published private(set) var now = Date()
    /// Treat events titled like breaks (Lunch, Gym, Walk) as free time. Saved in the app's own sandboxed preferences.
    @Published var countBreaksAsFree = UserDefaults.standard.object(forKey: "countBreaksAsFree") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(countBreaksAsFree, forKey: "countBreaksAsFree")
            refresh()
        }
    }
    @Published private(set) var today: DayForecast
    @Published private(set) var outlook: [DayForecast]
    @Published private(set) var isRequestingAccess = false

    let settings = ForecastSettings()
    /// Created once access is granted: a calendar store made before that can keep returning nothing.
    private var reader: CalendarReader?
    private var observer: NSObjectProtocol?

    init() {
        let now = Date()
        let sample = SampleCalendar.intervals(around: now)
        today = ForecastEngine.forecast(for: now, intervals: sample)
        outlook = ForecastEngine.outlook(after: now, days: 5, intervals: sample)
        observer = NotificationCenter.default.addObserver(forName: CalendarReader.didChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func requestAccess() async {
        isRequestingAccess = true
        defer { isRequestingAccess = false }
        // Also watch for the answer directly, so a reply that never arrives can't leave onboarding stuck.
        let watcher = Task { @MainActor [weak self] in
            while !Task.isCancelled, CalendarReader.access == .notDetermined {
                try? await Task.sleep(for: .milliseconds(400))
            }
            self?.refresh()
        }
        _ = await CalendarReader.requestAccess()
        watcher.cancel()
        refresh()
    }

    func refresh() {
        now = Date()
        access = CalendarReader.access
        if access == .granted, reader == nil {
            reader = CalendarReader()
        }
        // Until access is granted, the onboarding screen shows a made-up day.
        let intervals = if access == .granted, let reader {
            reader.busyIntervals(in: ForecastEngine.fetchWindow(from: now), countingBreaksAsFree: countBreaksAsFree)
        } else {
            SampleCalendar.intervals(around: now)
        }
        today = ForecastEngine.forecast(for: now, intervals: intervals, settings: settings)
        outlook = ForecastEngine.outlook(after: now, days: 5, intervals: intervals, settings: settings)
        if access == .granted {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
