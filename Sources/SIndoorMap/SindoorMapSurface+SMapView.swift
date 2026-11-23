#if os(iOS)
import CoreLocation
import Foundation
import SMap

/// SMapView as the navigator's map: its indoor layer and its points, circles and lines with the layer option `indoor`.
extension SMapView: SindoorMapSurface {
    public func sindoorAddIndoor(_ id: String, geojson: [String: Any], level: String?, control: Bool) async throws {
        try await addIndoor(id, source: .geojson(geojson), options: SMapIndoorOptions(level: level, control: control))
    }

    public func sindoorAddDot(_ id: String, at c: CLLocationCoordinate2D, style: SindoorDotStyle, indoor: SMapIndoorRef) throws {
        var o = SMapPointOptions(color: SMapColor(smapHex: style.color), radius: style.radius,
                                 strokeColor: SMapColor(smapHex: style.strokeColor), strokeWidth: style.strokeWidth, zIndex: 1001)
        o.indoor = indoor
        try addPoints(id, [SMapPoint(lat: c.latitude, lng: c.longitude)], options: o)
    }

    public func sindoorAddCircle(_ id: String, center c: CLLocationCoordinate2D, radiusM: Double, color: String, opacity: Double, indoor: SMapIndoorRef) throws {
        var o = SMapCircleOptions(radius: .constant(radiusM), area: SMapPolygonOptions(fill: SMapColor(smapHex: color), opacity: opacity, zIndex: 1000))
        o.indoor = indoor
        try addCircles(id, data: .points([SMapPoint(lat: c.latitude, lng: c.longitude)]), options: o)
    }

    public func sindoorAddLine(_ id: String, coordinates: [CLLocationCoordinate2D], color: String, width: Double, indoor: SMapIndoorRef) throws {
        var o = SMapLineOptions(color: SMapColor(smapHex: color), width: width, zIndex: 999)
        o.indoor = indoor
        try addLines(id, [SMapLine(coordinates)], options: o)
    }
}
#endif
