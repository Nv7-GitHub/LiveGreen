import CoreLocation
import MapKit
import GreenCore

/// Where the user is, for finding stores near them. Asks for when-in-use permission once; without it (denied, or
/// no fix within a few seconds) falls back to the centre of the state the profile names, then Cambridge, MA.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    /// Harvard Square, for a profile with no state.
    static let fallback = CLLocation(latitude: 42.3736, longitude: -71.1190)

    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<CLLocation?, Never>] = []
    private var last: CLLocation?
    /// "Cambridge, MA" for the last fix, once reverse-geocoded.
    private(set) var locality: String?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// The current location, a recent fix, or the fallback for `region`.
    func location(region: Region) async -> CLLocation {
        if let last, last.timestamp.timeIntervalSinceNow > -600 { return last }
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return Self.center(of: region)
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
        let fix = await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask { await self.requestFix() }
            group.addTask {
                try? await Task.sleep(for: .seconds(6))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let fix {
            last = fix
            await geocode(fix)
            return fix
        }
        return Self.center(of: region)
    }

    private func requestFix() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
            manager.requestLocation()
        }
    }

    private func geocode(_ location: CLLocation) async {
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else { return }
        locality = item.addressRepresentations?.cityWithContext
    }

    private func finish(_ location: CLLocation?) {
        let continuations = waiting
        waiting = []
        for continuation in continuations { continuation.resume(returning: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.finish(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .denied || status == .restricted { self.finish(nil) }
        }
    }

    static func center(of region: Region) -> CLLocation {
        guard let state = region.usState, let center = USStateCenters.all[state] else { return fallback }
        return CLLocation(latitude: center.latitude, longitude: center.longitude)
    }
}

/// Points of interest near a location from Apple Maps, closest first.
enum NearbyPlaceSearch {
    /// Runs the queries in order and returns the first that finds anything within `radius` metres, up to `limit`.
    static func search(_ queries: [String], near location: CLLocation, radius: CLLocationDistance = 8_000,
                       limit: Int = 6) async -> [NearbyPlace] {
        for query in queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .pointOfInterest
            request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: radius * 2,
                                                longitudinalMeters: radius * 2)
            guard let response = try? await MKLocalSearch(request: request).start() else { continue }
            let places = response.mapItems.compactMap { item -> NearbyPlace? in
                let itemLocation = item.location
                let distance = itemLocation.distance(from: location)
                guard distance <= radius, let name = item.name else { return nil }
                return NearbyPlace(name: name, address: item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
                                       ?? item.address?.shortAddress,
                                   latitude: itemLocation.coordinate.latitude, longitude: itemLocation.coordinate.longitude,
                                   distanceMeters: distance, phone: item.phoneNumber, url: item.url,
                                   categoryName: item.pointOfInterestCategory.map(Self.title))
            }
            .sorted { ($0.distanceMeters ?? 0) < ($1.distanceMeters ?? 0) }
            if !places.isEmpty { return Array(places.prefix(limit)) }
        }
        return []
    }

    /// "MKPOICategoryFoodMarket" → "Food market".
    static func title(_ category: MKPointOfInterestCategory) -> String {
        let raw = category.rawValue.replacingOccurrences(of: "MKPOICategory", with: "")
        var words: [String] = []
        for character in raw {
            if character.isUppercase || words.isEmpty { words.append(String(character)) } else { words[words.count - 1].append(character) }
        }
        let joined = words.joined(separator: " ").lowercased()
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }
}

/// Rough geographic centres of US states, for when location is off.
enum USStateCenters {
    static let all: [String: CLLocationCoordinate2D] = [
        "AL": .init(latitude: 32.8, longitude: -86.8), "AK": .init(latitude: 61.4, longitude: -150.0),
        "AZ": .init(latitude: 33.45, longitude: -112.07), "AR": .init(latitude: 34.75, longitude: -92.29),
        "CA": .init(latitude: 37.77, longitude: -122.42), "CO": .init(latitude: 39.74, longitude: -104.99),
        "CT": .init(latitude: 41.76, longitude: -72.68), "DE": .init(latitude: 39.74, longitude: -75.55),
        "DC": .init(latitude: 38.9, longitude: -77.04), "FL": .init(latitude: 28.54, longitude: -81.38),
        "GA": .init(latitude: 33.75, longitude: -84.39), "HI": .init(latitude: 21.31, longitude: -157.86),
        "ID": .init(latitude: 43.62, longitude: -116.2), "IL": .init(latitude: 41.88, longitude: -87.63),
        "IN": .init(latitude: 39.77, longitude: -86.16), "IA": .init(latitude: 41.59, longitude: -93.62),
        "KS": .init(latitude: 39.05, longitude: -95.68), "KY": .init(latitude: 38.25, longitude: -85.76),
        "LA": .init(latitude: 29.95, longitude: -90.07), "ME": .init(latitude: 43.66, longitude: -70.26),
        "MD": .init(latitude: 39.29, longitude: -76.61), "MA": .init(latitude: 42.3736, longitude: -71.1190),
        "MI": .init(latitude: 42.33, longitude: -83.05), "MN": .init(latitude: 44.98, longitude: -93.27),
        "MS": .init(latitude: 32.3, longitude: -90.18), "MO": .init(latitude: 38.63, longitude: -90.2),
        "MT": .init(latitude: 45.78, longitude: -108.5), "NE": .init(latitude: 41.26, longitude: -95.94),
        "NV": .init(latitude: 36.17, longitude: -115.14), "NH": .init(latitude: 42.99, longitude: -71.46),
        "NJ": .init(latitude: 40.74, longitude: -74.17), "NM": .init(latitude: 35.08, longitude: -106.65),
        "NY": .init(latitude: 40.71, longitude: -74.0), "NC": .init(latitude: 35.23, longitude: -80.84),
        "ND": .init(latitude: 46.88, longitude: -96.79), "OH": .init(latitude: 39.96, longitude: -83.0),
        "OK": .init(latitude: 35.47, longitude: -97.52), "OR": .init(latitude: 45.52, longitude: -122.68),
        "PA": .init(latitude: 39.95, longitude: -75.17), "RI": .init(latitude: 41.82, longitude: -71.41),
        "SC": .init(latitude: 32.78, longitude: -79.93), "SD": .init(latitude: 43.55, longitude: -96.73),
        "TN": .init(latitude: 36.16, longitude: -86.78), "TX": .init(latitude: 30.27, longitude: -97.74),
        "UT": .init(latitude: 40.76, longitude: -111.89), "VT": .init(latitude: 44.48, longitude: -73.21),
        "VA": .init(latitude: 37.54, longitude: -77.44), "WA": .init(latitude: 47.61, longitude: -122.33),
        "WV": .init(latitude: 38.35, longitude: -81.63), "WI": .init(latitude: 43.07, longitude: -89.4),
        "WY": .init(latitude: 41.14, longitude: -104.82),
    ]
}
