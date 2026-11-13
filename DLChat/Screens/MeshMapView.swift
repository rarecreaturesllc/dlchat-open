import CoreLocation
import DLCore
import SwiftUI

/// Mesh Map data: radios this phone's radio has heard, radios meshmap.net lists (downloaded on request,
/// through Tor when Tor is on), and the phone's own location to measure from. Everything stays in
/// memory and is gone when the map closes; the location is never stored or sent.
@MainActor
@Observable
final class MeshMapModel: NSObject, CLLocationManagerDelegate {
    private(set) var worldwide: [MeshNode] = []
    private(set) var loadingWorldwide = false
    private(set) var worldwideNote: String?
    private(set) var here: CLLocation?
    private(set) var locationNote: String?

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if Launch().screen == .meshmap, LaunchSwitches.arguments.contains("-seed-demo") { seedDemo() }
    }

    // MARK: Location

    var locationAllowed: Bool { [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) }
    var locationDenied: Bool { [.denied, .restricted].contains(manager.authorizationStatus) }

    /// Asks iOS (once) and starts updates while the map is open.
    func useLocation() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if locationAllowed { manager.startUpdatingLocation() }
        else { locationNote = "Location is off for DLChat. Allow it in iOS Settings > DLChat to see distances." }
    }

    func stop() { manager.stopUpdatingLocation() }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if self.locationAllowed { self.locationNote = nil; self.manager.startUpdatingLocation() }
            else if self.locationDenied { self.locationNote = "Location is off for DLChat. Allow it in iOS Settings > DLChat to see distances." }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.here = last }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: Worldwide

    /// Downloads meshmap.net's list. Through Tor when Tor is on (fails closed while it starts); straight
    /// over the internet only when the person has turned Tor off.
    func loadWorldwide(online: OnlineModel) async {
        guard !loadingWorldwide else { return }
        var port: UInt16?
        if online.torOn {
            guard online.isOn else { worldwideNote = "Worldwide radios download through Tor, which runs with online chat. Turn on online chat in Settings first."; return }
            guard let torPort = online.torPort else { worldwideNote = "Waiting for Tor to connect. Try again in a moment."; return }
            port = torPort
        }
        loadingWorldwide = true
        worldwideNote = online.torOn ? "Downloading through Tor…" : "Downloading without Tor…"
        defer { loadingWorldwide = false }
        guard let data = await RelayPool.download(MeshMap.worldwideURL, socksPort: port, isolation: "meshmap", maxBytes: MeshMap.maxWorldwideBytes) else {
            worldwideNote = "Could not get the list from meshmap.net. Check the connection and try again."
            return
        }
        guard let nodes = await Task.detached(operation: { MeshMap.parseWorldwide(data) }).value else {
            worldwideNote = "meshmap.net sent something DLChat cannot read."
            return
        }
        worldwide = nodes
        worldwideNote = "\(nodes.count.formatted()) radios from meshmap.net, which collects them from radios that share over the internet."
    }

    // MARK: Measuring

    func distance(to node: MeshNode) -> Double? {
        guard let here, let lat = node.latitude, let lon = node.longitude else { return nil }
        return MeshMap.distance(fromLat: here.coordinate.latitude, lon: here.coordinate.longitude, toLat: lat, lon: lon)
    }

    func bearing(to node: MeshNode) -> Double? {
        guard let here, let lat = node.latitude, let lon = node.longitude else { return nil }
        return MeshMap.bearing(fromLat: here.coordinate.latitude, lon: here.coordinate.longitude, toLat: lat, lon: lon)
    }

    // MARK: Demo (screenshots only)

    @ObservationIgnored private(set) var demoRadio: [MeshNode] = []

    private func seedDemo() {
        let lat = 37.7749, lon = -122.4194
        here = CLLocation(latitude: lat, longitude: lon)
        let ago = { (m: Double) in Date().addingTimeInterval(-m * 60) }
        demoRadio = [
            MeshNode(num: 0xA1, longName: "Porch radio", latitude: lat + 0.008, longitude: lon + 0.009, lastHeard: ago(1), hops: 0, source: .radio),
            MeshNode(num: 0xA2, longName: "Hilltop relay", latitude: lat + 0.043, longitude: lon + 0.002, lastHeard: ago(3), hops: 1, source: .radio),
            MeshNode(num: 0xA3, longName: "K4 base", latitude: lat - 0.040, longitude: lon + 0.055, lastHeard: ago(12), hops: 2, source: .radio),
            MeshNode(num: 0x9F2C, lastHeard: ago(60), hops: 1, source: .radio),
        ]
        worldwide = [
            MeshNode(num: 0xB1, longName: "Twin Peaks", latitude: lat - 0.022, longitude: lon - 0.028, lastHeard: ago(5), model: "RAK4631", source: .worldwide),
            MeshNode(num: 0xB2, longName: "Oakland hills", latitude: 37.8044, longitude: -122.2012, lastHeard: ago(20), model: "T_ECHO", source: .worldwide),
        ]
        worldwideNote = "2 radios from meshmap.net (demo)."
    }
}

/// Mesh Map, the fourth tab: a street map (only through Tor) or, without Tor, a radar of radios by
/// direction and distance; or a list. Tap a radio for its details. Distances in miles or kilometres.
struct MeshMapView: View {
    let mesh: MeshtasticModel
    let online: OnlineModel
    @State private var map = MeshMapModel()
    @State private var mode = 0
    @State private var showRadio = true
    @State private var showWorldwide = true
    @State private var rangeIndex = 1
    @State private var selected: MeshNode?
    /// The radio whose bubble is open on the radar (first tap); a tap on the bubble opens `selected`.
    @State private var bubble: MeshNode?
    @AppStorage("meshmap.miles") private var miles = MeshMap.prefersMiles()
    @Environment(\.colorSchemeContrast) private var contrast

    private var ranges: [Double] { MeshMap.ranges(miles: miles) }
    private var range: Double { ranges[min(rangeIndex, ranges.count - 1)] }
    /// The street map loads only through Tor; never straight over the internet.
    private var torPort: UInt16? { online.isOn && online.torOn ? online.torPort : nil }

    private var radioNodes: [MeshNode] { map.demoRadio.isEmpty ? Array(mesh.nodes.values) : map.demoRadio }

    private var shown: [MeshNode] {
        let all = (showRadio ? radioNodes : []) + (showWorldwide ? map.worldwide : [])
        if map.here != nil {
            return all.sorted { (map.distance(to: $0) ?? .infinity) < (map.distance(to: $1) ?? .infinity) }
        }
        return all.sorted { ($0.lastHeard ?? .distantPast) > ($1.lastHeard ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DLSpace.md) {
                HStack {
                    Text("Mesh map").font(.dl(.title2, .semibold)).foregroundStyle(Color.dlText)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    unitsToggle
                }
                TabSlider(selection: $mode, labels: ["Map", "List"])
                sources
                location
                if mode == 0 { mapView } else { list }
                worldwideControls
                Text("Your own radio's location sharing is off, so it is not on anyone's map. Your location stays on this phone.")
                    .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
            }
            .padding(DLSpace.md)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { if map.locationAllowed { map.useLocation() } }
        .onDisappear { map.stop() }
        .sheet(item: $selected) { node in
            MeshNodeDetail(node: node, distance: map.distance(to: node), bearing: map.bearing(to: node), miles: miles) { selected = nil }
        }
    }

    // MARK: Pieces

    private var unitsToggle: some View {
        Button { Haptics.tap(); miles.toggle() } label: {
            Text(miles ? "mi" : "km").font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlText)
                .frame(minWidth: DLSize.control, minHeight: DLSize.control)
                .background(Color.dlPanel, in: RoundedRectangle.key)
                .overlay { RoundedRectangle.key.stroke(contrast == .increased ? Color.dlSoft : Color.dlHairline, lineWidth: 1) }
        }
        .accessibilityLabel("Units")
        .accessibilityValue(miles ? "Miles" : "Kilometres")
        .accessibilityHint("Switches between miles and kilometres")
        .accessibilityIdentifier("meshmap-units")
    }

    private var sources: some View {
        HStack(spacing: DLSpace.xs) {
            chip("Your radio · \(radioNodes.count)", on: $showRadio, id: "meshmap-source-radio")
            chip("Worldwide · \(map.worldwide.count)", on: $showWorldwide, id: "meshmap-source-world")
        }
    }

    private func chip(_ title: String, on: Binding<Bool>, id: String) -> some View {
        Button { Haptics.tap(); on.wrappedValue.toggle() } label: {
            Text(title).font(.dl(.subheadline, .semibold))
                .foregroundStyle(on.wrappedValue ? Color.dlNight : Color.dlSoft)
                .padding(.horizontal, DLSpace.md).frame(minHeight: 44)
                .background(on.wrappedValue ? Color.dlText : Color.dlPanel, in: RoundedRectangle.key)
                .overlay { RoundedRectangle.key.stroke(contrast == .increased ? Color.dlSoft : Color.dlHairline, lineWidth: 1) }
        }
        .accessibilityAddTraits(on.wrappedValue ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private var location: some View {
        if map.here == nil {
            VStack(alignment: .leading, spacing: DLSpace.xs) {
                Text(map.locationNote ?? "Distances need this phone's location. It stays on this phone, only while the map is open.")
                    .font(.dl(.subheadline)).foregroundStyle(map.locationNote == nil ? Color.dlSoft : Color.dlWarn)
                if !map.locationDenied {
                    Button("Use my location") { map.useLocation() }.buttonStyle(.dlSecondary)
                        .accessibilityIdentifier("meshmap-location")
                }
            }
        }
    }

    // MARK: Map (streets through Tor, else radar)

    private var mapView: some View {
        VStack(alignment: .leading, spacing: DLSpace.sm) {
            if let torPort {
                MeshStreetMap(torPort: torPort, nodes: onMap, here: map.here?.coordinate, rangeMetres: range, summary: summary) { selected = $0 }
                    .frame(height: 380)
                    .clipShape(RoundedRectangle.key)
                    .overlay { RoundedRectangle.key.stroke(Color.dlHairline, lineWidth: 1) }
                    .accessibilityIdentifier("meshmap-streets")
                Text("Pinch and drag to see more. Tap a dot for a summary, then tap the summary for details. Streets download through Tor from OpenFreeMap, so it sees a Tor address, not yours. Nothing is saved on this phone.")
                    .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
            } else {
                radar
                Text("Tap a dot for a summary, then tap the summary for details. Hollow dots are farther than the edge, shown in their direction.")
                    .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
                Text(streetNote).font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
            }
            rangePicker
            HStack(spacing: DLSpace.md) {
                legend(Color.dlGo, "Heard by your radio")
                legend(Color.dlText.opacity(0.75), "Worldwide")
            }
            let hidden = shown.filter { !$0.hasLocation }.count
            if hidden > 0 {
                Text("\(hidden) more \(hidden == 1 ? "radio shares" : "radios share") no location: see the list.")
                    .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
            }
        }
    }

    private var streetNote: String {
        if !online.torOn { return "The street map loads only through Tor, and Tor is off. Turn it on in Settings to see streets." }
        if !online.isOn { return "The street map loads through Tor, which runs with online chat. Turn on online chat in Settings to see streets." }
        return "Connecting to Tor. The street map appears once it is ready."
    }

    private var rangePicker: some View {
        HStack(spacing: DLSpace.xs) {
            ForEach(ranges.indices, id: \.self) { i in
                let on = i == min(rangeIndex, ranges.count - 1)
                Button { Haptics.select(); rangeIndex = i } label: {
                    Text(MeshMap.format(metres: ranges[i], miles: miles)).font(.dl(.subheadline, .semibold))
                        .foregroundStyle(on ? Color.dlNight : Color.dlSoft)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? Color.dlText : Color.dlPanel, in: RoundedRectangle.key)
                }
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var radar: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2 - 14
            let center = CGPoint(x: geo.size.width / 2, y: size / 2)
            ZStack {
                ForEach(1...3, id: \.self) { ring in
                    Circle().stroke(Color.dlHairline, lineWidth: 1)
                        .frame(width: radius * 2 * CGFloat(ring) / 3, height: radius * 2 * CGFloat(ring) / 3)
                        .position(center)
                }
                Path { p in
                    p.move(to: CGPoint(x: center.x, y: center.y - radius)); p.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                    p.move(to: CGPoint(x: center.x - radius, y: center.y)); p.addLine(to: CGPoint(x: center.x + radius, y: center.y))
                }
                .stroke(Color.dlHairline.opacity(0.6), lineWidth: 1)
                Text("N").font(.dl(.caption, .semibold)).foregroundStyle(Color.dlSoft)
                    .position(x: center.x, y: center.y - radius - 8)
                ForEach(1...3, id: \.self) { ring in
                    Text(MeshMap.format(metres: range * Double(ring) / 3, miles: miles))
                        .font(.dl(.caption2)).foregroundStyle(Color.dlSoft).fixedSize()
                        .position(x: center.x + radius * CGFloat(ring) / 3 - 18, y: center.y + 10)
                }
                Circle().fill(Color.dlText).frame(width: 12, height: 12)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
                    .position(center)
                    .accessibilityLabel("You")
                ForEach(onMap) { node in
                    if let p = radarPoint(node, center: center, radius: radius) {
                        let far = (map.distance(to: node) ?? 0) > range
                        let color = node.source == .radio ? Color.dlGo : Color.dlText.opacity(0.75)
                        Button { Haptics.tap(); bubble = bubble?.id == node.id ? nil : node } label: {
                            // Farther than the range: drawn hollow on the edge, in its direction.
                            Circle().fill(far ? Color.clear : color).overlay { Circle().stroke(color, lineWidth: 2) }
                                .frame(width: 10, height: 10)
                                .frame(width: 44, height: 44)  // VoiceOver and touch need a 44pt target, not the 10pt dot
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .position(p)
                        .accessibilityLabel("\(node.displayName), \(detail(node))")
                        .accessibilityHint("Shows a summary")
                    }
                }
                if let node = bubble, let p = radarPoint(node, center: center, radius: radius) {
                    Button { Haptics.tap(); selected = node; bubble = nil } label: {
                        HStack(spacing: DLSpace.xs) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(node.displayName).font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlText)
                                Text(summary(node)).font(.dl(.caption)).foregroundStyle(Color.dlSoft)
                            }
                            Image(systemName: "chevron.right").font(.dl(.caption, .semibold)).foregroundStyle(Color.dlSoft)
                                .accessibilityHidden(true)
                        }
                        .fixedSize()
                        .padding(.horizontal, DLSpace.sm).padding(.vertical, DLSpace.xs)
                        .frame(minHeight: 44)
                        .background(Color.dlPanel, in: RoundedRectangle.key)
                        .overlay { RoundedRectangle.key.stroke(Color.dlHairline, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    // Above the dot, kept inside the radar.
                    .position(x: min(max(p.x, 110), geo.size.width - 110), y: p.y > 60 ? p.y - 40 : p.y + 40)
                    .accessibilityHint("Shows details")
                    .accessibilityIdentifier("meshmap-bubble")
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Radar, \(onMap.count) radios; edge is \(MeshMap.format(metres: range, miles: miles))")
        .accessibilityIdentifier("meshmap-radar")
    }

    /// Every radio with a location, whatever the range (the range buttons only zoom). Nearest 2000 at
    /// most, so the worldwide list cannot stall the map.
    private var onMap: [MeshNode] { Array(shown.filter(\.hasLocation).prefix(2000)) }

    /// Where a radio sits on the radar; farther than the range, on the edge in its direction.
    private func radarPoint(_ node: MeshNode, center: CGPoint, radius: CGFloat) -> CGPoint? {
        guard let d = map.distance(to: node), let b = map.bearing(to: node) else { return nil }
        let r = radius * CGFloat(min(d / range, 1))
        let angle = (b - 90) * .pi / 180
        return CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
    }

    /// The bubble's one line: distance and direction, and when it was last heard.
    private func summary(_ node: MeshNode) -> String {
        var parts: [String] = []
        if let d = map.distance(to: node), let b = map.bearing(to: node) { parts.append(MeshMap.format(metres: d, miles: miles) + " " + MeshMap.compass(b)) }
        if let heard = node.lastHeard { parts.append(heard.formatted(.relative(presentation: .named))) }
        return parts.isEmpty ? (node.source == .radio ? "Your radio" : "Worldwide") : parts.joined(separator: " · ")
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(text).font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
        }
    }

    // MARK: List

    @ViewBuilder private var list: some View {
        let rows = Array(shown.prefix(200))
        if rows.isEmpty {
            Text(mesh.isActive ? "No radios yet. Your radio lists others as it hears them; you can also load worldwide radios below."
                           : "Turn on the radio in Settings to see the radios it hears, or load worldwide radios below.")
                .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft)
        }
        LazyVStack(spacing: DLSpace.xs) {
            ForEach(rows) { node in
                Button { Haptics.tap(); selected = node } label: {
                    HStack(spacing: DLSpace.sm) {
                        Circle().fill(node.hasLocation ? (node.source == .radio ? Color.dlGo : Color.dlText) : Color.dlEdge)
                            .frame(width: 10, height: 10).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.displayName).font(.dl(.body, .semibold)).foregroundStyle(Color.dlText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(detail(node)).font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.dl(.footnote, .semibold)).foregroundStyle(Color.dlSoft)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, DLSpace.md).padding(.vertical, DLSpace.sm)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .background(Color.dlPanel, in: RoundedRectangle.key)
                    .overlay { RoundedRectangle.key.stroke(Color.dlHairline, lineWidth: 1) }
                    .contentShape(RoundedRectangle.key)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Shows details")
            }
        }
        if shown.count > rows.count {
            Text("Showing the \(rows.count) \(map.here == nil ? "most recently heard" : "nearest") of \(shown.count.formatted()).")
                .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
        }
    }

    private func detail(_ node: MeshNode) -> String {
        var parts: [String] = []
        if let d = map.distance(to: node), let b = map.bearing(to: node) {
            parts.append(MeshMap.format(metres: d, miles: miles) + " " + MeshMap.compass(b))
        } else if !node.hasLocation {
            parts.append("No location")
        }
        if let hops = node.hops { parts.append(hops == 0 ? "direct" : hops == 1 ? "1 hop" : "\(hops) hops") }
        if let heard = node.lastHeard { parts.append(heard.formatted(.relative(presentation: .named))) }
        parts.append(node.source == .radio ? "your radio" : "worldwide")
        return parts.joined(separator: " · ")
    }

    // MARK: Worldwide

    private var worldwideControls: some View {
        VStack(alignment: .leading, spacing: DLSpace.xs) {
            DLLegend("Worldwide radios")
                .accessibilityAddTraits(.isHeader)
            Text(map.worldwideNote ?? "Download meshmap.net's public list of radios that share their location over the internet (about 4 MB). Through Tor when Tor is on, so meshmap.net does not see your address.")
                .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft)
            Button(map.loadingWorldwide ? "Downloading…" : (map.worldwide.isEmpty ? "Load worldwide radios" : "Refresh worldwide radios")) {
                Task { await map.loadWorldwide(online: online) }
            }
            .buttonStyle(.dlSecondary).disabled(map.loadingWorldwide)
            .accessibilityIdentifier("meshmap-load-world")
        }
    }
}

/// One radio's details, from a tap on the map or the list.
struct MeshNodeDetail: View {
    let node: MeshNode
    let distance: Double?
    let bearing: Double?
    let miles: Bool
    let done: () -> Void

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: DLSpace.md) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(node.displayName).font(.dl(.title2, .semibold)).foregroundStyle(Color.dlText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("Done") { Haptics.tap(); done() }.font(.dl(.headline)).foregroundStyle(Color.dlText)
                            .frame(minWidth: DLSize.control, minHeight: DLSize.control)
                    }
                    VStack(spacing: 0) {
                        ForEach(rows, id: \.0) { label, value in
                            HStack(alignment: .firstTextBaseline) {
                                Text(label).font(.dl(.subheadline)).foregroundStyle(Color.dlSoft)
                                Spacer(minLength: DLSpace.md)
                                Text(value).font(.dl(.body, .semibold)).foregroundStyle(Color.dlText)
                                    .multilineTextAlignment(.trailing).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, DLSpace.md).frame(minHeight: 48)
                            .accessibilityElement(children: .combine)
                            if label != rows.last?.0 { Divider().overlay(Color.dlHairline) }
                        }
                    }
                    .background(Color.dlPanel, in: RoundedRectangle.key)
                    .overlay { RoundedRectangle.key.stroke(Color.dlHairline, lineWidth: 1) }
                    Text(node.source == .radio ? "Your radio heard this one over the air."
                                               : "From meshmap.net's public list. Its owner chose to share its location over the internet.")
                        .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
                }
                .padding(DLSpace.md)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("meshmap-detail")
    }

    private var rows: [(String, String)] {
        var r: [(String, String)] = []
        if !node.shortName.isEmpty { r.append(("Short name", node.shortName)) }
        r.append(("Radio ID", "!" + String(format: "%08x", node.num)))
        if let model = node.model, !model.isEmpty { r.append(("Model", model)) }
        r.append(("Source", node.source == .radio ? "Heard by your radio" : "Worldwide"))
        if let distance, let bearing {
            r.append(("Distance", MeshMap.format(metres: distance, miles: miles) + " " + MeshMap.compass(bearing)))
        }
        if let lat = node.latitude, let lon = node.longitude {
            r.append(("Location", String(format: "%.4f, %.4f", lat, lon)))
        } else {
            r.append(("Location", "Not shared"))
        }
        if let hops = node.hops { r.append(("Hops away", hops == 0 ? "Direct" : "\(hops)")) }
        if let heard = node.lastHeard { r.append(("Last heard", heard.formatted(.relative(presentation: .named)))) }
        return r
    }
}
