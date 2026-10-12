import WidgetKit

struct GlanceEntry: TimelineEntry {
    let date: Date
    let glance: Glance?
}

/// The widgets and complications show the last glance the app stored. The app reloads them whenever it stores a new one;
/// the timeline only adds an entry at midnight, so yesterday's scores start saying "Yesterday" on their own.
struct GlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), glance: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        completion(GlanceEntry(date: Date(), glance: context.isPreview ? (GlanceStore.load() ?? .sample) : GlanceStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let now = Date(), glance = GlanceStore.load()
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        let entries = [GlanceEntry(date: now, glance: glance), GlanceEntry(date: midnight, glance: glance)]
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(86_400))))
    }
}

extension Glance {
    /// What the widget gallery shows before there is real data.
    static let sample = Glance(v: 1, at: nil, date: nil, units: "metric", recovery: 72, band: "high", strain: 9.8, strainLo: 10, strainHi: 14,
                               sleep: 84, asleep: 452, hrv: 61, rhr: 52, water: Water(ml: 1200, goal: 2500), next: nil)
}
