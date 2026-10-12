import SwiftUI
import WidgetKit

/// The iPhone's widgets and the workout Live Activity. The app stores today's glance (GlanceStore) whenever the page's
/// numbers change and reloads the timelines; these views only draw it.
@main
struct BaselineWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        WorkoutLiveActivity()
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BaselineToday", provider: GlanceProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Recovery, strain, sleep and water against your own baselines.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GlanceEntry

    var body: some View {
        content.containerBackground(for: .widget) { background }
    }

    @ViewBuilder private var content: some View {
        if let g = entry.glance {
            switch family {
            case .systemSmall: SmallView(g: g, age: g.age(now: entry.date))
            case .systemMedium: MediumView(g: g, age: g.age(now: entry.date))
            case .accessoryCircular: CircularView(g: g)
            case .accessoryRectangular: RectangularView(g: g, age: g.age(now: entry.date))
            default: InlineView(g: g, age: g.age(now: entry.date))
            }
        } else {
            NoData(family: family)
        }
    }

    @ViewBuilder private var background: some View {
        switch family {
        case .systemSmall, .systemMedium: Palette.background
        default: Color.clear
        }
    }
}

/// A score ring like the app's: a faint track and the value as an arc with a rounded end.
struct ScoreRing<Label: View>: View {
    var value: Double                // 0...1
    var color: Color
    var lineWidth: CGFloat
    @ViewBuilder var label: () -> Label

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label()
        }
        .padding(lineWidth / 2)
    }
}

private func caption(_ text: String) -> some View {
    Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
}

private struct SmallView: View {
    let g: Glance
    let age: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                caption("Recovery")
                Spacer(minLength: 4)
                if let age { caption(age).lineLimit(1) }
            }
            ScoreRing(value: (g.recovery ?? 0) / 100, color: Palette.recovery(g.band), lineWidth: 9) {
                Text(g.recoveryText).font(.system(size: 26, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                caption("Strain")
                Text(g.strainText).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Palette.strain)
                if let t = g.strainTargetText { Text("/ \(t)").font(.system(size: 12, design: .rounded)).foregroundStyle(.secondary) }
            }
        }
        .foregroundStyle(.white)
    }
}

private struct MediumView: View {
    let g: Glance
    let age: String?

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 6) {
                ScoreRing(value: (g.recovery ?? 0) / 100, color: Palette.recovery(g.band), lineWidth: 10) {
                    Text(g.recoveryText).font(.system(size: 28, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
                }
                caption(age.map { "Recovery · \($0)" } ?? "Recovery").lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: 112)
            VStack(alignment: .leading, spacing: 9) {
                row("Strain", g.strainText, g.strainTargetText.map { "target \($0)" }, Palette.strain)
                row("Sleep", g.sleepText, g.asleepText, Palette.sleep)
                if let w = g.water { waterRow(w) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
    }

    private func row(_ name: String, _ value: String, _ extra: String?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            caption(name)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(color)
                if let extra { Text(extra).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }

    private func waterRow(_ w: Glance.Water) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "drop.fill").font(.system(size: 11)).foregroundStyle(Palette.water)
                Text(Glance.waterText(ml: w.ml, goal: w.goal, imperial: g.imperial))
                    .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
            }
            ProgressView(value: min(w.ml, max(w.goal, 1)), total: max(w.goal, 1)).tint(Palette.water)
        }
    }
}

private struct CircularView: View {
    let g: Glance

    var body: some View {
        Gauge(value: min(100, max(0, g.recovery ?? 0)), in: 0...100) {
            Text("REC")
        } currentValueLabel: {
            Text(g.recovery.map { "\(Int($0.rounded()))" } ?? "–").font(.system(.body, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(Palette.recovery(g.band))
    }
}

private struct RectangularView: View {
    let g: Glance
    let age: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Recovery \(g.recoveryText)").font(.system(.headline, design: .rounded))
            Text("Strain \(g.strainText) · Sleep \(g.sleepText)").font(.system(.subheadline, design: .rounded))
            if let line = age ?? g.asleepText.map({ "Slept \($0)" }) {
                Text(line).font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineView: View {
    let g: Glance
    let age: String?

    var body: some View {
        if let age {
            Text("\(age): \(g.recoveryText) recovery")
        } else {
            Text("\(g.recoveryText) recovery · \(g.strainText) strain")
        }
    }
}

private struct NoData: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 20, weight: .semibold))
        case .accessoryInline:
            Text("Open Baseline to sync")
        default:
            VStack(alignment: .leading, spacing: 4) {
                if family == .systemSmall || family == .systemMedium {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.strain)
                }
                Text("Open Baseline to sync").font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .foregroundStyle(.white)
        }
    }
}
