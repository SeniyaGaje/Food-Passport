import Network
import Observation

/// Connectivity is a hint; each request still handles its own error.
@Observable
final class NetworkMonitor {
    private(set) var isOffline = false
    private let monitor = NWPathMonitor()

    init() {
        // Called whenever the network changes; the flag is updated on the main thread.
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor in self?.isOffline = offline }
        }
        monitor.start(queue: DispatchQueue(label: "FoodPassport.Connectivity"))
    }

    deinit { monitor.cancel() }
}
