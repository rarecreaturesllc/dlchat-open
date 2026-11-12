import AVFoundation
import SwiftUI
import VisionKit

/// A message as a QR code, full screen, for the person next to you. Wipe stays one shield tap away.
struct QRShowView: View {
    let payload: String
    let lock: AppLock
    let wipe: () -> Bool
    let done: () -> Void
    @State private var safety = false

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            VStack(spacing: DLSpace.lg) {
                HStack {
                    Text("QR code").font(.dl(.title2, .bold)).foregroundStyle(Color.dlText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    SafetyButton { safety = true }
                    Button("Close") { Haptics.tap(); done() }.font(.dl(.headline)).foregroundStyle(Color.dlText)
                        .lineLimit(1).fixedSize().frame(minHeight: DLSize.control)
                        .accessibilityIdentifier("qr-close")
                }
                ScrollView {
                    VStack(spacing: DLSpace.lg) {
                        Text("Show this to the other phone").font(.dl(.headline)).foregroundStyle(Color.dlSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        QRCodeBox(text: payload, label: "QR code holding your sealed message")
                            .accessibilityIdentifier("message-qr")
                        Text("Only phones in this group can read it. Scanning works in person only.")
                            .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft).multilineTextAlignment(.center)
                    }
                }
                Button("Done", action: done).buttonStyle(.dlPrimary)
            }
            .padding(DLSpace.md)
        }
        .sheet(isPresented: $safety) { SafetyView(lock: lock, wipe: { let ok = wipe(); if ok { done() }; return ok }) { safety = false } }
    }
}

/// The code on a white card (scanners need dark on light), with a note when it is too long for one code.
struct QRCodeBox: View {
    let text: String
    let label: String

    var body: some View {
        if let image = QRImage.make(text) {
            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                .frame(maxWidth: 360).frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle.key)
                .accessibilityLabel(label)
        } else {
            Label("This message is too long for one QR code. Shorten it or use the words.", systemImage: "exclamationmark.triangle.fill")
                .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn)
        }
    }
}

/// The group phrase as a QR code, only while a finger is held on the button. Letting go hides it again.
/// The words above stay on screen as the way to share without holding.
struct HoldToShowPhrase: View {
    let phrase: String
    /// Resets by itself when the touch ends or iOS cancels it, so a lost touch can never leave the code showing.
    @GestureState private var held = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DLSpace.xs) {
            // Fades in once held; gone at once on letting go, never fading out.
            if held {
                QRCodeBox(text: phrase, label: "QR code holding the group phrase").accessibilityIdentifier("phrase-qr")
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
            Text(held ? "Let go to hide it" : "Hold to show the phrase as a QR code")
                .font(.dl(.title2, .bold)).foregroundStyle(Color.dlGo)
                .frame(maxWidth: .infinity, minHeight: DLSize.primary)
                .background(Color.dlPanel, in: RoundedRectangle.key)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).updating($held) { _, held, _ in held = true })
                .onChange(of: held) { _, now in if now { Haptics.tap() } }
                .accessibilityLabel("Hold to show the phrase as a QR code")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("hold-phrase-qr")
        }
        .animation(reduceMotion ? nil : DLMotion.press, value: held)
    }
}

/// Camera scanner for QR codes. The camera is asked for at first use; frames stay in memory and are not stored.
/// The callback gets the code's text and returns true when it was accepted (the sheet then closes), or
/// false to keep scanning and show `rejected`.
struct QRScanView: View {
    let title: String
    let rejected: String
    let onFound: (String) -> Bool
    let done: () -> Void

    @State private var camera = CameraState.checking
    @State private var note: String?

    enum CameraState { case checking, ready, denied, unsupported }

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            VStack(spacing: DLSpace.md) {
                HStack {
                    Text(title).font(.dl(.title2, .bold)).foregroundStyle(Color.dlText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Close") { Haptics.tap(); done() }.font(.dl(.headline)).foregroundStyle(Color.dlText)
                        .lineLimit(1).fixedSize().frame(minHeight: DLSize.control)
                        .accessibilityIdentifier("scan-close")
                }
                switch camera {
                case .checking:
                    Spacer()
                case .ready:
                    QRScanner { text in
                        if onFound(text) {
                            Haptics.success()
                            done()
                        } else {
                            note = rejected
                        }
                    }
                    .clipShape(RoundedRectangle.key)
                    .accessibilityLabel("Camera view for scanning a QR code")
                case .denied:
                    problem("The camera is off for DLChat. Turn it on in the Settings app, or use the words instead.")
                case .unsupported:
                    problem("This phone cannot scan QR codes here. Use the words instead.")
                }
                if let note {
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("The camera only looks for the code. Nothing it sees is saved or sent.")
                    .font(.footnote).foregroundStyle(Color.dlSoft).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DLSpace.md)
        }
        .preferredColorScheme(.dark)
        .task { await checkCamera() }
    }

    private func problem(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).font(.dl(.body)).foregroundStyle(Color.dlSoft).multilineTextAlignment(.center)
                .accessibilityIdentifier("scan-problem")
            Spacer()
        }
    }

    private func checkCamera() async {
        guard DataScannerViewController.isSupported else { camera = .unsupported; return }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        camera = DataScannerViewController.isAvailable ? .ready : .denied
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
            recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        // Scanning can only start once the view is on screen.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            try? controller.startScanning()
        }
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onFound = onFound
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onFound: (String) -> Void
        private var lastText: String?
        private var lastTime = Date.distantPast

        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let code) in addedItems {
                guard let text = code.payloadStringValue else { continue }
                // The same code is reported again as it moves in view; pass it on at most every 2 seconds.
                if text == lastText, Date().timeIntervalSince(lastTime) < 2 { continue }
                lastText = text
                lastTime = Date()
                onFound(text)
            }
        }
    }
}
