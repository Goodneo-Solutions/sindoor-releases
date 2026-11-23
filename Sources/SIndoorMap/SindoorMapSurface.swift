// Built where sMap's SMap module exists (iOS, or any platform with sMap from source).
#if canImport(SMap)
import CoreLocation
import Foundation
import SIndoor
import SMap

/// What the navigator needs of a map: sMap's indoor layer (`addIndoor` and its level calls) and three kinds of drawing
/// tied to a level of it (the layer option `indoor`). `SMapView` conforms (SindoorMapSurface+SMapView.swift); a test
/// or another map may conform too. The names of the level calls are SMapView's own.
@MainActor
public protocol SindoorMapSurface: AnyObject {
    /// Draws a site's layer GeoJSON as the indoor layer `id`; returns once the map has it.
    func sindoorAddIndoor(_ id: String, geojson: [String: Any], level: String?, control: Bool) async throws
    func removeIndoor(_ id: String)
    func indoorLevel(_ id: String) throws -> String?
    func setIndoorLevel(_ id: String, _ level: String) throws
    @discardableResult
    func onIndoorLevelChange(_ listener: @escaping (SMapIndoorLevelChange) -> Void) -> Int
    func removeIndoorLevelChangeListener(_ token: Int)

    /// The blue dot: one point with a white ring.
    func sindoorAddDot(_ id: String, at: CLLocationCoordinate2D, style: SindoorDotStyle, indoor: SMapIndoorRef) throws
    /// The accuracy circle around it (radius in metres).
    func sindoorAddCircle(_ id: String, center: CLLocationCoordinate2D, radiusM: Double, color: String, opacity: Double, indoor: SMapIndoorRef) throws
    /// A route line.
    func sindoorAddLine(_ id: String, coordinates: [CLLocationCoordinate2D], color: String, width: Double, indoor: SMapIndoorRef) throws
    /// Removes a layer drawn above (an unknown id does nothing).
    func removeLayer(_ id: String)
}

/// How the blue dot looks.
public struct SindoorDotStyle: Equatable, Sendable {
    public var color: String
    public var radius: Double
    public var strokeColor: String
    public var strokeWidth: Double
    public init(color: String = "#1a73e8", radius: Double = 7, strokeColor: String = "#ffffff", strokeWidth: Double = 2) {
        self.color = color; self.radius = radius; self.strokeColor = strokeColor; self.strokeWidth = strokeWidth
    }
}
#endif
