import Foundation
import CoreLocation

enum LocationPermission: Equatable {
    case notDetermined
    /// Location while the app is open. Arrivals are detected only while FoodPassport is on screen.
    case whenInUse
    /// Location at any time. iOS also watches the restaurant geofences while the app is closed.
    case always
    case denied

    var allowsLocation: Bool {
        self == .whenInUse || self == .always
    }

    /// Shown in Profile → Location access.
    var label: String {
        switch self {
        case .notDetermined: "Not set"
        case .whenInUse: "While Using"
        case .always: "Always"
        case .denied: "Off"
        }
    }
}

/// Distances used for arrival alerts and visit verification.
enum Geofence {
    /// Walking inside this distance of a restaurant counts as arriving there.
    static let arrivalRadius: CLLocationDistance = 100
    /// A visit is "location verified" when it is logged within this distance of the restaurant.
    /// Slightly larger than the arrival radius to allow for GPS drift indoors.
    static let verificationRadius: CLLocationDistance = 150
    /// iOS lets one app monitor at most 20 regions at a time.
    static let maxMonitoredRestaurants = 20
}

/// Finds the student's location and watches restaurant geofences.
/// `AppState` only talks to this protocol, so unit tests can move a mock "student" around instead of using GPS.
protocol LocationService: AnyObject {
    var permission: LocationPermission { get }
    /// The most recent location, or nil when it isn't known yet.
    var currentLocation: CLLocation? { get }

    /// Called with each new location while updates are running.
    var onLocationChange: ((CLLocation) -> Void)? { get set }
    /// Called when the student changes location access, including in the Settings app.
    var onPermissionChange: ((LocationPermission) -> Void)? { get set }
    /// Called with a restaurant ID when iOS reports the student entered that restaurant's geofence.
    var onEnterRestaurant: ((Restaurant.ID) -> Void)? { get set }

    /// Shows the "Allow While Using App" prompt the first time, then returns the student's answer.
    func requestWhenInUsePermission() async -> LocationPermission
    /// Asks iOS to upgrade to "Always", so arrivals are noticed with the phone in a pocket.
    /// iOS decides whether and when to show this prompt, so the answer arrives later through `onPermissionChange`.
    func requestAlwaysPermission()

    func startUpdatingLocation()
    func stopUpdatingLocation()

    /// Replaces the watched geofences with ones around the nearest of these restaurants.
    func monitorArrivals(at restaurants: [Restaurant])
    func stopMonitoringArrivals()
}

/// `LocationService` backed by Core Location: live location updates plus `CLCircularRegion` monitoring.
final class CoreLocationService: NSObject, LocationService, CLLocationManagerDelegate {
    var onLocationChange: ((CLLocation) -> Void)?
    var onPermissionChange: ((LocationPermission) -> Void)?
    var onEnterRestaurant: ((Restaurant.ID) -> Void)?

    private let manager = CLLocationManager()
    private var permissionContinuation: CheckedContinuation<LocationPermission, Never>?

    override init() {
        super.init()
        // Set up at launch: if iOS relaunches the app in the background for a geofence,
        // the event is delivered to this delegate.
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // Ignore movements under 20 m so the app isn't recalculating distances constantly.
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

    /// Distance from the student, or the stored campus distance when their location isn't known yet.
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
    // Core Location calls these on the thread that created the manager, which is the main thread here.

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
        // Usually a temporary "location unknown". Core Location keeps trying, and the last known location is kept.
    }
}

/// In-memory `LocationService` for previews and unit tests. Tests move the "student" with `simulateMove(to:)`.
final class MockLocationService: LocationService {
    var permission: LocationPermission
    var currentLocation: CLLocation?
    /// What the student answers when the permission prompt appears.
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

    /// Pretends the student walked to `coordinate`.
    func simulateMove(to coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        currentLocation = location
        onLocationChange?(location)
    }

    /// Pretends iOS reported that the student entered a restaurant's geofence.
    func simulateGeofenceEntry(at restaurantID: Restaurant.ID) {
        onEnterRestaurant?(restaurantID)
    }
}
