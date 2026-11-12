import Charts
import SwiftUI

/// Meshtastic history: how long the Meshtastic chats are kept, and how many messages the public
/// channel carried per hour or per day while DLChat was connected to the radio.
struct MeshHistoryView: View {
    let mesh: MeshtasticModel
    @State private var pending: Retention?
    @State private var byDay = false
    @State private var channelIndex: UInt32?

    var body: some View {
        List {
            keepSection
            activitySection
        }
        .listStyle(.grouped).listRowSeparatorTint(Color.dlHairline).scrollContentBackground(.hidden)
        .background(Color.dlNight)
        .navigationTitle("Meshtastic history")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { mesh.purgeExpired() }
    }

    // MARK: Keep

    private var keepSection: some View {
        Section {
            Picker("Keep Meshtastic chats", selection: Binding(get: { mesh.keep }, set: choose)) {
                ForEach(Retention.allCases) { Text(Self.title($0)).tag($0) }
            }
            .pickerStyle(.menu).frame(minHeight: DLSize.control)
            .listRowBackground(Color.dlNight)
            .accessibilityIdentifier("mesh-keep")
            .confirmationDialog("Keep Meshtastic chats \(pending.map(Self.phrase) ?? "")?",
                                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                Button(pending == .off ? "Erase kept chats" : "Erase older messages", role: .destructive) {
                    Haptics.tap()
                    if let pending { mesh.setKeep(pending) }
                    pending = nil
                }
            } message: {
                Text(pending == .off
                     ? "Kept Meshtastic messages and counts are erased from this iPhone now. What is on screen goes when DLChat closes. This cannot be undone."
                     : "Meshtastic messages and counts older than this are erased now. This cannot be undone.")
            }
            let kept = mesh.archive.totalTexts
            Text(mesh.keep == .off
                 ? "Nothing is saved. Meshtastic messages and counts stay in memory and are gone when DLChat closes."
                 : "\(kept) \(kept == 1 ? "message" : "messages") kept, sealed on this iPhone with your other DLChat data. Wipe and the duress PIN erase them. Up to \(MeshArchive.maxTotal) messages; the oldest go first.")
                .font(.dl(.footnote)).foregroundStyle(Color.dlSoft).listRowBackground(Color.dlNight)
                .accessibilityIdentifier("mesh-keep-note")
        } header: {
            Text("Keep").font(.dl(.footnote, .semibold)).foregroundStyle(Color.dlSoft)
        } footer: {
            Text("Keeping them longer means anyone who gets into this iPhone and past your PIN can read what was said on the public channel and in your direct messages, who sent it and when, and when you were in range of the mesh.")
                .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
        }
    }

    static func title(_ value: Retention) -> String {
        switch value {
        case .off: return "Until DLChat closes"
        case .forever: return "Until you wipe"
        default: return value.title
        }
    }

    /// "Kept …" in a sentence: "until DLChat closes", "for 7 days", "until you wipe".
    static func phrase(_ value: Retention) -> String {
        switch value {
        case .off: return "until DLChat closes"
        case .forever: return "until you wipe"
        default: return "for " + value.title
        }
    }

    private func choose(_ new: Retention) {
        let old = mesh.keep.seconds ?? .infinity
        if (new.seconds ?? .infinity) < old, mesh.keep != .off { pending = new } else { mesh.setKeep(new) }
    }

    // MARK: Activity

    /// The public channel by default; any of the radio's channels when it has more than one.
    private var shownChannel: UInt32 {
        channelIndex ?? mesh.channels.first(where: \.keyIsPublic)?.index ?? mesh.channels.first?.index ?? 0
    }

    private var bars: [MeshBar] {
        mesh.archive.series(channel: shownChannel, bucket: byDay ? .day : .hour, count: byDay ? 30 : 24, now: Date())
    }

    private var activitySection: some View {
        let bars = bars
        let heard = bars.compactMap(\.count).reduce(0, +)
        let busiest = bars.filter { ($0.count ?? 0) > 0 }.max { ($0.count ?? 0) < ($1.count ?? 0) }
        let gaps = bars.contains { $0.count == nil }
        return Section {
            if mesh.channels.count > 1 {
                Picker("Channel", selection: Binding(get: { shownChannel }, set: { channelIndex = $0 })) {
                    ForEach(mesh.channels) { Text($0.title(preset: mesh.presetName)).tag($0.index) }
                }
                .pickerStyle(.menu).frame(minHeight: DLSize.control).listRowBackground(Color.dlNight)
            }
            DLSegments(selection: $byDay, options: [false, true]) { $0 ? "Last 30 days" : "Last 24 hours" }
                .listRowBackground(Color.dlNight).listRowInsets(EdgeInsets())
            .accessibilityIdentifier("mesh-activity-range")
            VStack(alignment: .leading, spacing: DLSpace.sm) {
                Text("\(heard) \(heard == 1 ? "message" : "messages") heard")
                    .font(.dl(.headline)).foregroundStyle(Color.dlText)
                    .accessibilityIdentifier("mesh-activity-total")
                if let busiest, let n = busiest.count {
                    Text("Busiest \(byDay ? "day" : "hour"): \(label(busiest)), \(n)")
                        .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
                }
                chart(bars)
            }
            .padding(.vertical, DLSpace.xs)
            .listRowBackground(Color.dlNight)
        } header: {
            Text("Channel activity").font(.dl(.footnote, .semibold)).foregroundStyle(Color.dlSoft)
        } footer: {
            Text("Counts messages from other radios, not yours. Only counted while DLChat is open and connected to your radio\(gaps ? ": empty spaces are times it was not" : ""). Counts are kept like the messages above.")
                .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
        }
    }

    private func chart(_ bars: [MeshBar]) -> some View {
        Chart(bars) { bar in
            if let n = bar.count {
                BarMark(x: .value(byDay ? "Day" : "Hour", bar.start, unit: byDay ? .day : .hour), y: .value("Messages", n))
                    .foregroundStyle(Color.dlGo)
            }
        }
        .chartXScale(domain: (bars.first?.start ?? Date())...(bars.last?.end ?? Date()))
        .chartXAxis {
            AxisMarks(values: .stride(by: byDay ? .day : .hour, count: byDay ? 7 : 6)) { _ in
                AxisGridLine().foregroundStyle(Color.dlHairline)
                AxisValueLabel(format: byDay ? Date.FormatStyle.dateTime.month(.abbreviated).day() : Date.FormatStyle.dateTime.hour())
                    .foregroundStyle(Color.dlSoft)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color.dlHairline)
                AxisValueLabel().foregroundStyle(Color.dlSoft)
            }
        }
        .frame(height: 180)
        .accessibilityElement()
        .accessibilityLabel(byDay ? "Messages per day, last 30 days" : "Messages per hour, last 24 hours")
        .accessibilityValue(bars.compactMap { b in b.count.map { "\(label(b)): \($0)" } }.joined(separator: ", "))
        .accessibilityIdentifier("mesh-activity-chart")
    }

    private func label(_ bar: MeshBar) -> String {
        byDay ? bar.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
              : bar.start.formatted(date: Calendar.current.isDateInToday(bar.start) ? .omitted : .abbreviated, time: .shortened)
    }
}
