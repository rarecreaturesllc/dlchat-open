import SwiftUI

/// First run, right after the PIN: offers to make a group for the people the person trusts. Create goes
/// straight to New group; "I have an invite" goes to Join; Skip leaves them in the app with no group (the
/// Meshtastic radio can still be turned on in Settings). Asked once; nothing here is saved but the answer.
struct WelcomeView: View {
    let create: () -> Void
    let join: () -> Void
    let skip: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: DLSpace.md) {
                        Spacer(minLength: DLSpace.lg)
                        Image(systemName: "person.3.fill")
                            .font(.system(size: typeSize.isAccessibilitySize ? 36 : 48, weight: .semibold))
                            .foregroundStyle(Color.dlGo).accessibilityHidden(true)
                        Text("Create a group for friends or family?")
                            .font(.dl(.largeTitle, .bold)).foregroundStyle(Color.dlText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("welcome-title")
                        Text("A group is the few people you trust to read your messages. Make it on this phone, then hand it to each of them in person.")
                            .font(.dl(.body)).foregroundStyle(Color.dlSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: DLSpace.lg)
                        Button("Create a group", action: create)
                            .buttonStyle(.dlPrimary).accessibilityIdentifier("welcome-create")
                        Button("I have an invite", action: join)
                            .buttonStyle(.dlSecondary).accessibilityIdentifier("welcome-join")
                        Button { Haptics.tap(); skip() } label: {
                            Text("Skip for now").font(.dl(.headline)).foregroundStyle(Color.dlText)
                                .frame(maxWidth: .infinity, minHeight: DLSize.control)
                        }
                        .accessibilityIdentifier("welcome-skip")
                        Text("You can make or join a group any time from the Chat tab. To use a Meshtastic radio without a group, turn it on in Settings.")
                            .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
                            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(DLSpace.lg)
                    .frame(minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// The first-run sheet: the welcome question, then New group or Join in the same sheet, so nothing has
/// to wait for one sheet to close before the next opens.
struct FirstRunView: View {
    let model: GroupModel
    let done: () -> Void
    @State private var step: Step = .welcome

    enum Step { case welcome, create, join }

    var body: some View {
        switch step {
        case .welcome:
            WelcomeView(create: { Onboarding.markDone(); step = .create },
                        join: { Onboarding.markDone(); step = .join },
                        skip: { Onboarding.markDone(); done() })
                .interactiveDismissDisabled()
        case .create:
            GroupSetupView(model: model, done: done)
        case .join:
            GroupSetupView(model: model, joinFirst: true, done: done)
        }
    }
}
