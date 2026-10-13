import CoreLocation
import MapKit
import UIKit

/// The map under a workout's route: Apple Maps for the area around it, and where each route point lands on that picture,
/// so the page can draw the route over it in its own colours (by pace).
enum RouteMap {
    /// { img: JPEG data URL, w, h (points), xy: [[x, y]] per route point }, or nil without a route or a map.
    static func snapshot(of route: [CLLocation], width: Double, dark: Bool) async -> [String: Any]? {
        guard route.count > 1 else { return nil }
        let lats = route.map(\.coordinate.latitude), lons = route.map(\.coordinate.longitude)
        guard let lat0 = lats.min(), let lat1 = lats.max(), let lon0 = lons.min(), let lon1 = lons.max() else { return nil }
        let w = min(max(width, 240), 600), h = (w * 0.62).rounded()
        let options = MKMapSnapshotter.Options()
        options.size = CGSize(width: w, height: h)
        // a margin around the route, and never closer in than a few streets
        options.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (lat0 + lat1) / 2, longitude: (lon0 + lon1) / 2),
                                            span: MKCoordinateSpan(latitudeDelta: max(0.004, (lat1 - lat0) * 1.4), longitudeDelta: max(0.004, (lon1 - lon0) * 1.4)))
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        options.traitCollection = UITraitCollection.current.modifyingTraits {
            $0.userInterfaceStyle = dark ? .dark : .light
            $0.displayScale = 2
        }
        guard let shot = try? await MKMapSnapshotter(options: options).start(),
              let jpeg = shot.image.jpegData(compressionQuality: 0.8) else { return nil }
        let xy = route.map { l -> [Double] in
            let p = shot.point(for: l.coordinate)
            let x = Double(p.x), y = Double(p.y)
            return [(x * 10).rounded() / 10, (y * 10).rounded() / 10]
        }
        return ["img": "data:image/jpeg;base64," + jpeg.base64EncodedString(), "w": w, "h": h, "xy": xy]
    }
}
