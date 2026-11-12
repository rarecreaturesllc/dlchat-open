import DLCore
import MapLibre
import SwiftUI

/// The street map behind the Mesh Map's Map view: MapLibre (open source) drawing OpenFreeMap's dark
/// OpenStreetMap style. Built only with Tor's port, and every download it makes (style, map pieces,
/// fonts, icons) goes through Tor, so the map service sees a Tor exit, never this phone. No map pieces
/// are cached on disk, so the phone keeps no record of the areas viewed. This is the only file that
/// uses MapLibre (HygieneTests).
struct MeshStreetMap: UIViewRepresentable {
    static let styleURL = URL(string: "https://tiles.openfreemap.org/styles/dark")!

    let torPort: UInt16
    /// Every radio with a location; the map shows whichever fall inside the area in view.
    let nodes: [MeshNode]
    let here: CLLocationCoordinate2D?
    /// The range buttons only zoom: the area from the centre to the edge, in metres.
    let rangeMetres: Double
    /// One line under the name in the bubble (distance, direction, last heard).
    let summary: (MeshNode) -> String
    /// A tap on the bubble opens the radio's full details.
    let onSelect: (MeshNode) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> MLNMapView {
        // Must be set before the map makes its first request.
        let config = RelayPool.configuration(socksPort: torPort, isolation: "map")
        config.httpAdditionalHeaders = ["User-Agent": "DLChat-iOS"]  // OpenFreeMap asks apps to identify themselves
        MLNNetworkConfiguration.sharedManager.sessionConfiguration = config
        MLNOfflineStorage.shared.setMaximumAmbientCacheSize(0) { _ in }
        let map = MLNMapView(frame: .zero, styleURL: Self.styleURL)
        map.delegate = context.coordinator
        map.logoView.isHidden = true            // attribution (OpenStreetMap, OpenFreeMap) stays, as required
        map.compassViewPosition = .topRight
        map.showsUserLocation = false           // DLChat draws "You" itself; MapLibre never reads location
        map.backgroundColor = UIColor(Color.dlNight)
        map.accessibilityLabel = "Street map of radios around you"
        context.coordinator.watchBubbleTaps(on: map)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let c = context.coordinator
        c.onSelect = onSelect
        // Pins are replaced only when the radios or their places change, not on every redraw.
        let key = nodes.map { "\($0.id)\($0.latitude ?? 0),\($0.longitude ?? 0)" } + [here.map { "you\($0.latitude),\($0.longitude)" } ?? ""]
        if key != c.pinKey {
            c.pinKey = key
            if let old = map.annotations { map.removeAnnotations(old) }
            var pins: [MLNAnnotation] = nodes.compactMap { node in
                guard let lat = node.latitude, let lon = node.longitude else { return nil }
                let pin = NodePin(node: node)
                pin.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                pin.title = node.displayName
                pin.subtitle = summary(node)
                return pin
            }
            if let here {
                let you = MLNPointAnnotation()
                you.coordinate = here
                you.title = "You"
                pins.append(you)
            }
            map.addAnnotations(pins)
        }
        let center = here ?? nodes.first.flatMap { n in n.latitude.flatMap { lat in n.longitude.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } } }
        if c.lastRange != rangeMetres || (c.lastCenterKnown == false && center != nil), let center {
            c.lastRange = rangeMetres
            c.lastCenterKnown = true
            let dLat = rangeMetres / 111_000
            let dLon = dLat / max(cos(center.latitude * .pi / 180), 0.1)
            let bounds = MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: center.latitude - dLat, longitude: center.longitude - dLon),
                                             ne: CLLocationCoordinate2D(latitude: center.latitude + dLat, longitude: center.longitude + dLon))
            map.setVisibleCoordinateBounds(bounds, animated: true)
        }
    }

    final class NodePin: MLNPointAnnotation {
        let node: MeshNode
        init(node: MeshNode) { self.node = node; super.init() }
        required init?(coder: NSCoder) { nil }
    }

    final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        var onSelect: (MeshNode) -> Void
        var pinKey: [String] = []
        var lastRange: Double = 0
        var lastCenterKnown = false
        init(onSelect: @escaping (MeshNode) -> Void) { self.onSelect = onSelect }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            let node = (annotation as? NodePin)?.node
            let id = node == nil ? "you" : (node?.source == .radio ? "radio" : "world")
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) ?? {
                let v = MLNAnnotationView(reuseIdentifier: id)
                v.frame = CGRect(x: 0, y: 0, width: 44, height: 44)  // 44pt target around a small dot
                let dot = UIView(frame: CGRect(x: 15, y: 15, width: 14, height: 14))
                dot.layer.cornerRadius = 7
                dot.layer.borderWidth = 2
                dot.layer.borderColor = UIColor(Color.dlNight).cgColor
                dot.backgroundColor = id == "you" ? UIColor(Color.dlText) : (id == "radio" ? UIColor(Color.dlGo) : UIColor(Color.dlSoft))
                dot.isUserInteractionEnabled = false
                v.addSubview(dot)
                return v
            }()
            view.isAccessibilityElement = true
            view.accessibilityLabel = node.map { "\($0.displayName), \(annotation.subtitle.flatMap { $0 } ?? "")" } ?? "You"
            view.accessibilityTraits = node == nil ? [] : .button
            view.accessibilityHint = node == nil ? nil : "Shows a summary; tap the summary for details"
            return view
        }

        /// First tap: the bubble (name and one line). Tapping anywhere on the bubble opens the details.
        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool { annotation is NodePin }

        /// MapLibre's own "tap on the bubble" never fires on a phone: the map's single tap (which closes
        /// the bubble) takes the touch first. So the bubble gets its own tap, and the map's single tap
        /// waits for it to fail. It starts only for touches on the bubble and off the (i), which keeps its
        /// own tap.
        private let bubbleTap = UITapGestureRecognizer()
        private weak var infoButton: UIView?

        func watchBubbleTaps(on map: MLNMapView) {
            bubbleTap.addTarget(self, action: #selector(bubbleTapped(_:)))
            bubbleTap.delegate = self
            map.addGestureRecognizer(bubbleTap)
            for tap in map.gestureRecognizers ?? [] where tap !== bubbleTap {
                guard let tap = tap as? UITapGestureRecognizer, tap.numberOfTapsRequired == 1, tap.numberOfTouchesRequired == 1 else { continue }
                tap.require(toFail: bubbleTap)
            }
        }

        private func bubble(in map: MLNMapView) -> UIView? {
            map.subviews.first { $0 is MLNCalloutView && !$0.isHidden && $0.alpha > 0 }
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gesture === bubbleTap, let map = gesture.view as? MLNMapView,
                  map.selectedAnnotations.first is NodePin, let bubble = bubble(in: map) else { return false }
            if let info = infoButton, let touched = touch.view, touched.isDescendant(of: info) { return false }
            return bubble.bounds.contains(touch.location(in: bubble))
        }

        @objc private func bubbleTapped(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .recognized, let map = gesture.view as? MLNMapView,
                  let pin = map.selectedAnnotations.first as? NodePin else { return }
            Haptics.tap()
            map.deselectAnnotation(pin, animated: true)
            onSelect(pin.node)
        }

        /// Kept for VoiceOver, which activates the bubble without a touch.
        func mapView(_ mapView: MLNMapView, tapOnCalloutFor annotation: MLNAnnotation) {
            guard let pin = annotation as? NodePin else { return }
            mapView.deselectAnnotation(annotation, animated: true)
            onSelect(pin.node)
        }

        func mapView(_ mapView: MLNMapView, rightCalloutAccessoryViewFor annotation: MLNAnnotation) -> UIView? {
            guard annotation is NodePin else { return nil }
            let chevron = UIButton(type: .detailDisclosure)
            chevron.accessibilityLabel = "Details"
            infoButton = chevron
            return chevron
        }

        func mapView(_ mapView: MLNMapView, annotation: MLNAnnotation, calloutAccessoryControlTapped control: UIControl) {
            guard let pin = annotation as? NodePin else { return }
            Haptics.tap()  // the (i) button
            mapView.deselectAnnotation(annotation, animated: true)
            onSelect(pin.node)
        }
    }
}

/// Dragging the map pans it; it never changes tab (see `PageSwipe`).
extension MLNMapView: SideSwipeOwner {}
