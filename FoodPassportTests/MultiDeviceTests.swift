import Foundation
import Testing
import UIKit
@testable import FoodPassport

@Suite("Widgets and multi-device state")
@MainActor
struct MultiDeviceTests {
    @Test("The widget snapshot survives reopening and clears on sign-out")
    func widgetLifecycle() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = WidgetSnapshotStore(file: folder.appendingPathComponent("widget.json"))
        let publisher = RecordingWidgetPublisher(store: store)
        let app = TestApp(database: MockDatabaseService(visits: [], stamps: []), widgets: publisher)
        try await app.signIn()
        app.appState.updateMonthlyBudget(8000)
        app.appState.saveQuest(QuestSettings(startedAt: .now.addingTimeInterval(-3600)))
        app.appState.addVisit(makeVisit(amount: 1000, isLocationVerified: false))
        #expect(store.read().monthlySpent == 1000)
        #expect(store.read().monthlyBudget == 8000)
        #expect(store.read().cuisinesTried == 1)
        #expect(store.read().questTitle != nil)
        app.appState.signOut()
        #expect(!store.read().isSignedIn)
        #expect(store.read().monthlySpent == 0)
    }

    @Test("Month rollover resets spending and expired quests stop appearing")
    func widgetRollover() throws {
        let calendar = Calendar.current
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25)))
        let next = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let snapshot = WidgetSnapshot(isSignedIn: true, questTitle: "My quest", questEndsAt: next,
            monthlyBudget: 1000, monthlySpent: 1500, budgetMonth: WidgetSnapshot.monthKey(for: start))
        #expect(snapshot.budgetFraction == 1)
        #expect(snapshot.remainingBudget == 0)
        #expect(snapshot.current(at: next).monthlySpent == 0)
        #expect(snapshot.current(at: next).questTitle == nil)
        #expect(WidgetSnapshot().budgetFraction == 0)
    }

    @Test("Face ID locking removes personal widget values until unlocking")
    func widgetPrivacy() async throws {
        let publisher = RecordingWidgetPublisher()
        let app = TestApp(widgets: publisher)
        try await app.signIn()
        await app.appState.setFaceIDEnabled(true)
        app.appState.lockIfNeeded()
        #expect(!publisher.latest.isSignedIn)
        await app.appState.unlockWithBiometrics()
        #expect(publisher.latest.isSignedIn)
    }

    @Test("Quest settings persist and only visits after the start count")
    func savedQuestProgress() async throws {
        let app = TestApp(database: MockDatabaseService(visits: [], stamps: []))
        try await app.signIn()
        let started = Date.now.addingTimeInterval(-60)
        app.appState.saveQuest(QuestSettings(targetCuisines: 2, budget: 1200, startedAt: started))
        app.appState.addVisit(makeVisit(cuisine: .italian, amount: 800, date: started.addingTimeInterval(-1)))
        app.appState.addVisit(makeVisit(amount: 400))
        await app.appState.waitForPendingWrites()
        #expect(app.appState.activeQuest.spent == 400)
        #expect(app.appState.activeQuest.cuisinesTried == 1)
        #expect(app.database.quest?.targetCuisines == 2)
        let reloaded = TestApp(database: app.database)
        try await reloaded.signIn()
        #expect(reloaded.appState.questSettings == app.appState.questSettings)
    }

    @Test("Widget links select their destination and unknown links are ignored")
    func widgetRoutes() {
        let router = AppRouter()
        router.openWidgetURL(URL(string: "foodpassport://quest")!)
        #expect(router.selectedTab == .passport)
        router.openWidgetURL(URL(string: "foodpassport://budget")!)
        #expect(router.selectedTab == .profile)
        #expect(router.sheet == .monthlyBudget)
        router.openWidgetURL(URL(string: "https://quest")!)
        #expect(router.selectedTab == .profile)
    }

    @Test("Failed metadata saves can retry after the connection recovers")
    func retryChanges() async {
        let database = OfflineDatabaseService()
        let state = AppState(auth: MockAuthService(signedInUserID: "student"), database: database)
        await state.restoreSession()
        state.addVisit(makeVisit(id: "retry-visit", isLocationVerified: false))
        await state.waitForPendingWrites()
        #expect(state.hasFailedWrites)
        database.failsWrites = false
        state.retryFailedWrites()
        await state.waitForPendingWrites()
        #expect(!state.hasFailedWrites)
        #expect(database.writtenVisitIDs == ["retry-visit"])
    }

    @Test("Resetting cannot replay a previously failed visit save")
    func resetDropsFailedSaves() async {
        let database = OfflineDatabaseService()
        let state = AppState(auth: MockAuthService(signedInUserID: "student"), database: database)
        await state.restoreSession()
        state.addVisit(makeVisit(id: "cancelled-visit", isLocationVerified: false))
        await state.waitForPendingWrites()
        database.failsWrites = false
        state.resetAllData()
        state.retryFailedWrites()
        await state.waitForPendingWrites()
        #expect(database.writtenVisitIDs.isEmpty)
        #expect(state.visits.isEmpty)
    }

    @Test("A refresh error keeps the current passport and exposes a retry state")
    func failedRefresh() async throws {
        let database = OfflineDatabaseService()
        let state = AppState(auth: MockAuthService(signedInUserID: "student"), database: database)
        await state.restoreSession()
        let visits = state.visits
        database.failsReads = true
        await state.refreshData()
        #expect(state.visits == visits)
        #expect(state.loadError != nil)
        #expect(!state.isLoading)
        database.failsReads = false
        await state.refreshData()
        #expect(state.loadError == nil)
    }
}

@MainActor
final class RecordingWidgetPublisher: WidgetPublishing {
    var latest = WidgetSnapshot()
    let store: WidgetSnapshotStore?
    init(store: WidgetSnapshotStore? = nil) { self.store = store }
    func publish(_ snapshot: WidgetSnapshot) {
        latest = snapshot
        try? store?.save(snapshot)
    }
}
