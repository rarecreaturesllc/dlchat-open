import Foundation

/// One Meshtastic radio for the Mesh Map: heard by this phone's own radio, or listed by meshmap.net.
/// Names come from strangers' radios or the internet, so they are display text only, trimmed and capped.
public struct MeshNode: Equatable, Identifiable {
    public enum Source: Equatable { case radio, worldwide }

    public let num: UInt32
    public var longName: String
    public var shortName: String
    /// Degrees, or nil when the radio does not share a location.
    public var latitude: Double?
    public var longitude: Double?
    public var lastHeard: Date?
    /// Hops away from this phone's radio (radio source only); 0 is heard directly.
    public var hops: Int?
    public var model: String?
    /// The radio's Meshtastic public key (User.public_key, 32 bytes), used for direct messages. Radio source only.
    public var publicKey: Data?
    public let source: Source

    public var id: String { "\(source == .radio ? "r" : "w")\(num)" }
    public var hasLocation: Bool { latitude != nil && longitude != nil }
    public var displayName: String {
        let name = longName.isEmpty ? shortName : longName
        return name.isEmpty ? "Meshtastic \(String(num & 0xFFFF, radix: 16))" : name
    }

    public init(num: UInt32, longName: String = "", shortName: String = "", latitude: Double? = nil, longitude: Double? = nil,
                lastHeard: Date? = nil, hops: Int? = nil, model: String? = nil, publicKey: Data? = nil, source: Source) {
        self.num = num
        self.longName = MeshMap.clean(longName)
        self.shortName = MeshMap.clean(shortName)
        self.latitude = latitude
        self.longitude = longitude
        self.lastHeard = lastHeard
        self.hops = hops
        self.model = model.map(MeshMap.clean)
        self.publicKey = publicKey?.count == 32 ? publicKey : nil
        self.source = source
    }
}

public enum MeshMap {
    /// meshmap.net's public list of radios its internet feeds have seen (about 4 MB).
    public static let worldwideURL = URL(string: "https://meshmap.net/nodes.json")!
    /// Refuse anything far larger than the real file, so a bad answer cannot eat memory.
    public static let maxWorldwideBytes = 40 * 1024 * 1024

    static func clean(_ s: String) -> String {
        String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(40))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Meshtastic stores coordinates as degrees times 10^7. Zero means "no position".
    static func degrees(_ e7: Int64?) -> Double? {
        guard let e7, e7 != 0 else { return nil }
        let d = Double(e7) / 1e7
        return abs(d) <= 180 ? d : nil
    }

    /// meshmap.net's nodes.json: `{ "<num>": { longName, shortName, hwModel, latitude, longitude, seenBy: { topic: unixTime } } }`.
    /// Entries that do not parse are skipped. Nil only when the whole file is not that shape.
    public static func parseWorldwide(_ data: Data) -> [MeshNode]? {
        guard data.count <= maxWorldwideBytes,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return root.compactMap { key, value -> MeshNode? in
            guard let num = UInt32(key), let n = value as? [String: Any] else { return nil }
            let lat = degrees((n["latitude"] as? NSNumber)?.int64Value)
            let lon = degrees((n["longitude"] as? NSNumber)?.int64Value)
            let seen = (n["seenBy"] as? [String: Any])?.values.compactMap { ($0 as? NSNumber)?.doubleValue }.max()
            return MeshNode(num: num, longName: n["longName"] as? String ?? "", shortName: n["shortName"] as? String ?? "",
                            latitude: lat, longitude: lon == nil || lat == nil ? nil : lon,
                            lastHeard: seen.map(Date.init(timeIntervalSince1970:)), model: n["hwModel"] as? String,
                            source: .worldwide)
        }
    }

    // MARK: Geometry

    /// Great-circle distance in metres (haversine).
    public static func distance(fromLat lat1: Double, lon lon1: Double, toLat lat2: Double, lon lon2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = p2 - p1, dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Initial bearing in degrees clockwise from north, 0 up to 360.
    public static func bearing(fromLat lat1: Double, lon lon1: Double, toLat lat2: Double, lon lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180, dl = (lon2 - lon1) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    // MARK: Units

    public static let metresPerMile = 1609.344

    /// "1.2 km" / "0.7 mi": one decimal under 10, whole numbers above.
    public static func format(metres: Double, miles: Bool) -> String {
        let value = miles ? metres / metresPerMile : metres / 1000
        let unit = miles ? "mi" : "km"
        return value < 10 ? String(format: "%.1f \(unit)", value) : "\(Int(value.rounded())) \(unit)"
    }

    /// Radar ranges in metres: round numbers in the chosen unit.
    public static func ranges(miles: Bool) -> [Double] {
        miles ? [1, 3, 15, 60].map { $0 * metresPerMile } : [1, 5, 25, 100].map { $0 * 1000 }
    }

    /// Miles where the phone's region uses them (the US, the UK for distances, a few others).
    public static func prefersMiles(_ locale: Locale = .current) -> Bool {
        locale.measurementSystem == .us || locale.measurementSystem == .uk
    }

    /// Eight-point compass label for a bearing.
    public static func compass(_ bearing: Double) -> String {
        ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Int((bearing + 22.5).truncatingRemainder(dividingBy: 360) / 45) % 8]
    }
}

extension Meshtastic {
    /// A radio from a FromRadio node_info (the radio's own list of radios it has heard).
    public static func meshNode(fromNodeInfo data: Data) -> MeshNode? {
        guard let fields = Reader.fields(data), let info = fields.lastBytes(4), let n = Reader.fields(info) else { return nil }
        let num = UInt32(truncatingIfNeeded: n.lastVarint(1) ?? 0)
        guard num != 0 else { return nil }
        let user = n.lastBytes(2).flatMap(Reader.fields) ?? []
        let position = n.lastBytes(3).flatMap(Reader.fields) ?? []
        let (lat, lon) = coordinates(position)
        let heard = n.fixed32(5).flatMap { $0 == 0 ? nil : Date(timeIntervalSince1970: TimeInterval($0)) }
        return MeshNode(num: num, longName: user.string(2) ?? "", shortName: user.string(3) ?? "",
                        latitude: lat, longitude: lon, lastHeard: heard, hops: n.lastVarint(9).map { Int(clamping: $0) },
                        publicKey: user.lastBytes(8), source: .radio)
    }

    /// Position { latitude_i: sfixed32 = 1, longitude_i: sfixed32 = 2 } as degrees.
    public static func coordinates(_ position: [Field]) -> (Double?, Double?) {
        let lat = MeshMap.degrees(position.fixed32(1).map { Int64(Int32(bitPattern: $0)) })
        let lon = MeshMap.degrees(position.fixed32(2).map { Int64(Int32(bitPattern: $0)) })
        return lat == nil || lon == nil ? (nil, nil) : (lat, lon)
    }

    /// The POSITION_APP port: radios broadcast Position messages on it.
    public static let positionPort = 3
    /// The NODEINFO_APP port: radios broadcast their User (names) on it.
    public static let nodeInfoPort = 4
}
