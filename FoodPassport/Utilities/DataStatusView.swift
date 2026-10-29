import SwiftUI

/// One consistent status across tabs, detail screens and forms.
struct DataStatusView: View {
    @Environment(AppState.self) private var appState
    var body: some View {
        VStack(spacing: 4) {
            if appState.isOffline {
                Label("Offline · Cached data and on-device scanning are available. Photo uploads need a connection.",
                      systemImage: "wifi.slash")
                    .font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10).background(Theme.orangeTint)
            }
            if appState.isLoading {
                ProgressView("Refreshing your passport…").font(.footnote).padding(8)
            } else if let error = appState.loadError {
                HStack {
                    Text(error).font(.footnote)
                    Button("Retry") { Task { await appState.refreshData() } }
                        .frame(minHeight: 44)
                }.padding(.horizontal, 12).background(Theme.orangeTint)
            } else if appState.hasFailedWrites {
                HStack {
                    Text("Some changes haven't synced.").font(.footnote)
                    Button("Retry") { appState.retryFailedWrites() }.frame(minHeight: 44)
                }
            } else if appState.isSavingChanges {
                ProgressView(appState.isOffline ? "Waiting to sync changes…" : "Syncing changes…")
                    .font(.footnote).padding(8)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
