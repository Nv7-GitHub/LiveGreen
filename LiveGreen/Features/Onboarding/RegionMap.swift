import SwiftUI
import MapKit
import GreenCore

/// A map of where the user lives that flies in as the answer firms up: the globe, then the country, the US
/// state from the ZIP (straight from a bundled table), then the ZIP's own area once MapKit geocodes it.
/// Read-only, so the question still scrolls over it.
struct RegionMap: View {
    /// The region with state and grid zone already resolved (`USRegionLookup.resolved`).
    let region: Region

    @State private var camera = MapCameraPosition.camera(RegionMap.globe)
    @State private var pin: CLLocationCoordinate2D?

    private static let globe = MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 25, longitude: -40),
                                         distance: 24_000_000)

    /// What the map shows; a change flies the camera.
    private struct Place: Equatable {
        var countryCode: String
        var postalCode: String?
        var usState: String?
    }

    private var place: Place {
        let postal = region.postalCode?.trimmingCharacters(in: .whitespaces)
        return Place(countryCode: region.countryCode, postalCode: postal?.isEmpty == false ? postal : nil,
                     usState: region.usState)
    }

    var body: some View {
        Map(position: $camera, interactionModes: []) {
            if let pin {
                Marker(markerTitle, systemImage: "leaf.fill", coordinate: pin)
                    .tint(Theme.leaf)
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        // 170 pt, shrinking toward 110 pt when the question's scroll area is short (SE-size phones) so more of
        // the map peeks above the fold.
        .containerRelativeFrame(.vertical) { length, _ in min(170, max(110, length * 0.4)) }
        .clipShape(.rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.25)))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: place) { await locate(place) }
    }

    private var markerTitle: String {
        if place.countryCode == "US" { return place.postalCode ?? place.usState ?? "US" }
        return Locale.current.localizedString(forRegionCode: place.countryCode) ?? place.countryCode
    }

    /// Shows the best place known right away, then refines it with MapKit's geocoder (after a pause, so typing
    /// a ZIP does not send a request per digit). Offline, the coarser view stays.
    private func locate(_ place: Place) async {
        let isUS = place.countryCode == "US"
        if isUS, let state = place.usState, let center = Self.stateCenters[state] {
            fly(to: center, distance: state == "AK" ? 2_400_000 : 900_000)
        } else if isUS {
            fly(to: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.4), distance: 5_500_000)
        }
        // A US ZIP refines the state; elsewhere the postal code (if any) and then the country are looked up.
        let postal = isUS ? place.postalCode.flatMap { $0.count == 5 ? $0 : nil } : place.postalCode
        guard postal != nil || !isUS else { return }

        try? await Task.sleep(for: .milliseconds(postal == nil ? 100 : 600))
        let country = Locale(identifier: "en_US").localizedString(forRegionCode: place.countryCode) ?? place.countryCode
        let queries = [postal.map { "\($0), \(country)" }, isUS ? nil : country].compactMap { $0 }
        for query in queries {
            guard !Task.isCancelled else { return }
            guard let request = MKGeocodingRequest(addressString: query),
                  let item = (try? await request.mapItems)?.first else { continue }
            guard !Task.isCancelled else { return }
            fly(to: item.location.coordinate, distance: query == country ? 3_500_000 : 40_000)
            return
        }
    }

    private func fly(to center: CLLocationCoordinate2D, distance: Double) {
        withAnimation(.smooth(duration: 1.2)) {
            camera = .camera(MapCamera(centerCoordinate: center, distance: distance, pitch: distance < 100_000 ? 40 : 0))
            pin = center
        }
    }

    /// Approximate geographic centres of the US states and DC.
    private static let stateCenters: [String: CLLocationCoordinate2D] = {
        let degrees: [String: (Double, Double)] = [
            "AL": (32.8, -86.8), "AK": (64.0, -152.0), "AZ": (34.3, -111.7), "AR": (34.9, -92.4), "CA": (37.2, -119.5),
            "CO": (39.0, -105.5), "CT": (41.6, -72.7), "DE": (39.0, -75.5), "DC": (38.9, -77.0), "FL": (28.6, -82.4),
            "GA": (32.7, -83.4), "HI": (20.8, -156.3), "ID": (44.4, -114.6), "IL": (40.0, -89.2), "IN": (39.9, -86.3),
            "IA": (42.1, -93.5), "KS": (38.5, -98.4), "KY": (37.5, -85.3), "LA": (31.1, -92.0), "ME": (45.4, -69.2),
            "MD": (39.0, -76.8), "MA": (42.3, -71.8), "MI": (44.3, -85.4), "MN": (46.3, -94.3), "MS": (32.7, -89.7),
            "MO": (38.4, -92.5), "MT": (47.0, -109.6), "NE": (41.5, -99.8), "NV": (39.3, -116.6), "NH": (43.7, -71.6),
            "NJ": (40.2, -74.7), "NM": (34.4, -106.1), "NY": (42.9, -75.5), "NC": (35.6, -79.4), "ND": (47.5, -100.5),
            "OH": (40.3, -82.8), "OK": (35.6, -97.5), "OR": (43.9, -120.6), "PA": (40.9, -77.8), "RI": (41.7, -71.5),
            "SC": (33.9, -80.9), "SD": (44.4, -100.2), "TN": (35.9, -86.4), "TX": (31.5, -99.3), "UT": (39.3, -111.7),
            "VT": (44.1, -72.7), "VA": (37.5, -78.8), "WA": (47.4, -120.5), "WV": (38.6, -80.6), "WI": (44.6, -89.9),
            "WY": (43.0, -107.6),
        ]
        return degrees.mapValues { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }
    }()
}
