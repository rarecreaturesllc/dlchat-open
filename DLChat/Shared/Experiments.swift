import SwiftUI

/// Evolve flags: each candidate improvement lives behind one. Off in an App Store build no matter what;
/// test builds (Debug, TestFlight) can turn them on from Settings (long-press the version row), and Debug
/// builds also with the launch argument `-evolve_all YES`. Overrides live in their own defaults suite, apart from app data.
struct Experiment: Hashable, Identifiable {
    let key: String
    let title: String
    var id: String { key }

    /// One entry per iteration of the current Evolve cycle.
    static let all: [Experiment] = []
}

enum Experiments {
    private static let store = UserDefaults(suiteName: "evolve.experiments")!

    static var canOverride: Bool {
        #if DEBUG
        true
        #else
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    static func isOn(_ experiment: Experiment) -> Bool {
        guard canOverride else { return false }
        if LaunchSwitches.arguments.contains("-evolve_all") { return true }
        return store.bool(forKey: experiment.key)
    }

    static func set(_ experiment: Experiment, _ on: Bool) { store.set(on, forKey: experiment.key) }

    static func reset() { Experiment.all.forEach { store.removeObject(forKey: $0.key) } }
}

/// The hidden test screen: one switch per flag, all on, reset.
struct ExperimentsView: View {
    let done: () -> Void
    @State private var states: [String: Bool] = Dictionary(uniqueKeysWithValues: Experiment.all.map { ($0.key, Experiments.isOn($0)) })

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: DLSpace.md) {
                    HStack {
                        Text("Experiments").font(.dl(.title2, .semibold)).foregroundStyle(Color.dlText)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("Done") { Haptics.tap(); done() }.font(.dl(.headline)).foregroundStyle(Color.dlText)
                            .frame(minWidth: DLSize.control, minHeight: DLSize.control)
                    }
                    Text("Test builds only. Changes apply when a screen next opens.")
                        .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft)
                    if Experiment.all.isEmpty {
                        Text("No experiments in this build.").font(.dl(.body)).foregroundStyle(Color.dlText)
                    }
                    ForEach(Experiment.all) { experiment in
                        Toggle(experiment.title, isOn: Binding(
                            get: { states[experiment.key] ?? false },
                            set: { Experiments.set(experiment, $0); states[experiment.key] = $0 }))
                            .font(.dl(.body)).foregroundStyle(Color.dlText)
                            .frame(minHeight: DLSize.control)
                            .accessibilityIdentifier("experiment-\(experiment.key)")
                    }
                    Button("Turn all on") {
                        Experiment.all.forEach { Experiments.set($0, true); states[$0.key] = true }
                    }
                    .buttonStyle(.dlSecondary).accessibilityIdentifier("experiments-all-on")
                    Button("Reset") {
                        Experiments.reset()
                        Experiment.all.forEach { states[$0.key] = Experiments.isOn($0) }
                    }
                    .buttonStyle(.dlSecondary).accessibilityIdentifier("experiments-reset")
                }
                .padding(DLSpace.md)
            }
        }
        .tint(Color.dlGo)
        .preferredColorScheme(.dark)
    }
}
