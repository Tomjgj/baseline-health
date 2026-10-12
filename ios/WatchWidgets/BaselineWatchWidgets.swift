import SwiftUI
import WidgetKit

/// Complications for the watch face. The watch app stores the glance (GlanceStore) each time the phone sends a context
/// and reloads these; tapping one opens the watch app.
@main
struct BaselineWatchWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BaselineRecovery", provider: GlanceProvider()) { entry in
            ComplicationView(entry: entry)
        }
        .configurationDisplayName("Recovery")
        .description("Today's recovery, strain and sleep.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GlanceEntry

    var body: some View {
        content.containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder private var content: some View {
        let g = entry.glance
        switch family {
        case .accessoryCircular: circular(g)
        case .accessoryRectangular: rectangular(g, age: g?.age(now: entry.date))
        case .accessoryCorner: corner(g)
        default: inline(g, age: g?.age(now: entry.date))
        }
    }

    private func value(_ g: Glance?) -> Double { min(100, max(0, g?.recovery ?? 0)) }
    private func number(_ g: Glance?) -> String { g?.recovery.map { "\(Int($0.rounded()))" } ?? "–" }

    private func circular(_ g: Glance?) -> some View {
        Gauge(value: value(g), in: 0...100) {
            Text("REC")
        } currentValueLabel: {
            Text(number(g)).font(.system(.body, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(Palette.recovery(g?.band))
    }

    private func corner(_ g: Glance?) -> some View {
        Text(number(g))
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.recovery(g?.band))
            .widgetLabel {
                Gauge(value: value(g), in: 0...100) {
                    Text("Recovery")
                }
                .tint(Palette.recovery(g?.band))
            }
    }

    @ViewBuilder private func rectangular(_ g: Glance?, age: String?) -> some View {
        if let g {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Circle().fill(Palette.recovery(g.band)).frame(width: 8, height: 8)
                    Text("Recovery \(g.recoveryText)").font(.system(.headline, design: .rounded))
                }
                HStack(spacing: 6) {
                    Text("Strain \(g.strainText)").foregroundStyle(Palette.strain)
                    Text("Sleep \(g.sleepText)").foregroundStyle(Palette.sleep)
                }
                .font(.system(.body, design: .rounded))
                if let line = age ?? g.asleepText.map({ "Slept \($0)" }) {
                    Text(line).font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Open Baseline on your iPhone to sync").font(.system(.body, design: .rounded))
        }
    }

    @ViewBuilder private func inline(_ g: Glance?, age: String?) -> some View {
        if let g, let age {
            Text("\(age): \(g.recoveryText) recovery")
        } else if let g {
            Text("\(g.recoveryText) recovery · \(g.strainText) strain")
        } else {
            Text("Open Baseline to sync")
        }
    }
}
