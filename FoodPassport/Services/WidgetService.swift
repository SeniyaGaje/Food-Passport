import WidgetKit

protocol WidgetPublishing {
    func publish(_ snapshot: WidgetSnapshot)
}

struct AppWidgetPublisher: WidgetPublishing {
    func publish(_ snapshot: WidgetSnapshot) {
        do {
            try WidgetSnapshotStore().save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Widgets can show their last snapshot if the shared container is unavailable.
        }
    }
}

struct NoWidgetPublisher: WidgetPublishing {
    nonisolated init() {}
    func publish(_ snapshot: WidgetSnapshot) {}
}
