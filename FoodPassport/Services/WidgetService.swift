import WidgetKit

/// Sends the latest data to the widgets. A protocol, so tests can record it instead.
protocol WidgetPublishing {
    func publish(_ snapshot: WidgetSnapshot)
}

/// Writes the snapshot to the App Group file and asks WidgetKit to redraw the widgets.
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

/// Does nothing: for previews and tests without widgets.
struct NoWidgetPublisher: WidgetPublishing {
    nonisolated init() {}
    func publish(_ snapshot: WidgetSnapshot) {}
}
