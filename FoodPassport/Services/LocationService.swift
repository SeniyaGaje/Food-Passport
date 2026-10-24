import Foundation
import CoreLocation

enum LocationPermission: Equatable {
    case notDetermined
    /// Only while the app is open.
    case whenInUse
    /// Any time, so arrivals are noticed even when the app is closed.
    case always
    case denied

    var allowsLocation: Bool {
        self == .whenInUse || self == .always
    }

    /// Shown in Profile under Location access.
    var label: String {
        switch self {
        case .notDetermined: "Not set"
        case .whenInUse: "While Using"
        case .always: "Always"
        case .denied: "Off"
        }
    }
}

/// Distances for the arrival alert and for verifying visits.
enum Geofence {
    /// Coming this close to a restaurant counts as arriving.
    static let arrivalRadius: CLLocationDistance = 100
    /// A visit is verified if it's logged this close to the restaurant.
    /// A bit bigger than the arrival distance, because GPS is less accurate indoors.
    static let verificationRadius: CLLocationDistance = 150
    /// iOS lets an app watch at most 20 areas at a time.
    static let maxMonitoredRestaurants = 20
}

/// Finds the student's location and watches for them arriving at restaurants.
/// AppState only uses this protocol, so tests can move a fake "student" around instead of using GPS.
protocol LocationService: AnyObject {
    var permission: LocationPermission { get }
    /// The latest location, or nil if we don't know it yet.
    var currentLocation: CLLocation? { get }

    /// Runs every time the location changes.
    var onLocationChange: ((CLLocation) -> Void)? { get set }
    /// Runs when the student changes location access (even in Settings).
    var onPermissionChange: ((LocationPermission) -> Void)? { get set }
    /// Runs with a restaurant's ID when iOS says the student arrived there.
    var onEnterRestaurant: ((Restaurant.ID) -> Void)? { get set }

    /// Asks "Allow While Using App" the first time and returns the answer.
    func requestWhenInUsePermission() async -> LocationPermission
    /// Asks to upgrade to "Always", so arrivals work with the phone in a pocket.
    /// iOS decides when to ask, so the answer comes later through `onPermissionChange`.
    func requestAlwaysPermission()

    func startUpdatingLocation()
    func stopUpdatingLocation()

    /// Starts watching the nearest restaurants (replacing any watched before).
    func monitorArrivals(at restaurants: [Restaurant])
    func stopMonitoringArrivals()
}

/// The real location service, using Core Location (GPS plus a circle around each restaurant).
final class CoreLocationService: NSObject, LocationService, CLLocationManagerDelegate {
    var onLocationChange: ((CLLocation) -> Void)?
    var onPermissionChange: ((LocationPermission) -> Void)?
    var onEnterRestaurant: ((Restaurant.ID) -> Void)?

    private let manager = CLLocationManager()
    private var permissionContinuation: CheckedContinuation<LocationPermission, Never>?

    override init() {
        super.init()
        // Set up at launch, so an arrival that wakes the app in the background still reaches us.
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // Ignore moves under 20 m, so we're not recalculating all the time.
        manager.distanceFilter = 20
    }

    var permission: LocationPermission {
        Self.permission(from: manager.authorizationStatus)
    }

    var currentLocation: CLLocation? {
        manager.location
    }

    func requestWhenInUsePermission() async -> LocationPermission {
        guard permission == .notDetermined else { return permission }

        return await withCheckedContinuation { continuation in
            permissionContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func requestAlwaysPermission() {
        manager.requestAlwaysAuthorization()
    }

    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }

    func monitorArrivals(at restaurants: [Restaurant]) {
        stopMonitoringArrivals()
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        let nearest = restaurants
            .sorted { distance(to: $0) < distance(to: $1) }
            .prefix(Geofence.maxMonitoredRestaurants)

        for restaurant in nearest {
            let region = CLCircularRegion(center: restaurant.coordinate, radius: Geofence.arrivalRadius, identifier: restaurant.id)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
    }

    func stopMonitoringArrivals() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
    }

    /// Distance from the student, or the saved campus distance if we don't know where they are.
    private func distance(to restaurant: Restaurant) -> CLLocationDistance {
        guard let currentLocation else { return restaurant.distanceKm * 1000 }
        return currentLocation.distance(from: CLLocation(latitude: restaurant.latitude, longitude: restaurant.longitude))
    }

    private static func permission(from status: CLAuthorizationStatus) -> LocationPermission {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedWhenInUse: .whenInUse
        case .authorizedAlways: .always
        default: .denied
        }
    }

    // CLLocationManagerDelegate
    // These come in on the main thread, because that's where the manager was created.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            let permission = Self.permission(from: status)
            if permission != .notDetermined, let continuation = permissionContinuation {
                permissionContinuation = nil
                continuation.resume(returning: permission)
            }
            onPermissionChange?(permission)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        MainActor.assumeIsolated {
            onLocationChange?(latest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let restaurantID = region.identifier
        MainActor.assumeIsolated {
            onEnterRestaurant?(restaurantID)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Usually just "location unknown for now". Core Location keeps trying, so nothing to do.
    }
}

/// Fake location for previews and tests. Tests move the "student" with `simulateMove(to:)`.
final class MockLocationService: LocationService {
    var permission: LocationPermission
    var currentLocation: CLLocation?
    /// What the student taps when asked for permission.
    var answerWhenAsked: LocationPermission

    var onLocationChange: ((CLLocation) -> Void)?
    var onPermissionChange: ((LocationPermission) -> Void)?
    var onEnterRestaurant: ((Restaurant.ID) -> Void)?

    private(set) var isUpdatingLocation = false
    private(set) var monitoredRestaurantIDs: [Restaurant.ID] = []
    private(set) var hasRequestedAlwaysPermission = false

    init(
        permission: LocationPermission = .whenInUse,
        location: CLLocationCoordinate2D? = MockData.userLocation,
        answerWhenAsked: LocationPermission = .whenInUse
    ) {
        self.permission = permission
        self.currentLocation = location.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        self.answerWhenAsked = answerWhenAsked
    }

    func requestWhenInUsePermission() async -> LocationPermission {
        if permission == .notDetermined {
            permission = answerWhenAsked
            onPermissionChange?(permission)
        }
        return permission
    }

    func requestAlwaysPermission() {
        hasRequestedAlwaysPermission = true
    }

    func startUpdatingLocation() {
        isUpdatingLocation = true
        if let currentLocation {
            onLocationChange?(currentLocation)
        }
    }

    func stopUpdatingLocation() {
        isUpdatingLocation = false
    }

    func monitorArrivals(at restaurants: [Restaurant]) {
        monitoredRestaurantIDs = Array(restaurants.prefix(Geofence.maxMonitoredRestaurants).map(\.id))
    }

    func stopMonitoringArrivals() {
        monitoredRestaurantIDs = []
    }

    /// Pretend the student walked here.
    func simulateMove(to coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        currentLocation = location
        onLocationChange?(location)
    }

    /// Pretend iOS said the student arrived at this restaurant.
    func simulateGeofenceEntry(at restaurantID: Restaurant.ID) {
        onEnterRestaurant?(restaurantID)
    }
}
