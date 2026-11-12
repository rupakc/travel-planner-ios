import Domain
import Foundation
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@MainActor
@Suite struct CurrentPlanStoreTests {
    @Test func test_toggleDedupes() {
        let store = CurrentPlanStore(files: MemoryFileStore())
        let museum: JSONValue = ["name": "Museum", "price_usd": 20]
        store.toggle(field: "activities", item: museum)
        store.toggle(field: "activities", item: ["name": "Park"])
        #expect(store.selections["activities"].array?.count == 2)
        #expect(store.contains(field: "activities", item: ["name": "Museum"]))
        store.toggle(field: "activities", item: ["name": "Museum", "price_usd": 25])
        #expect(store.selections["activities"] == [["name": "Park"]])
        #expect(!store.contains(field: "activities", item: museum))
        #expect(store.isDirty)
    }

    @Test func test_planActionApplied() {
        let store = CurrentPlanStore(files: MemoryFileStore())
        store.apply(planAction: (action: "add", field: "activities", data: ["name": "Tower"]))
        store.apply(planAction: (action: "add", field: "activities", data: ["name": "Tower"]))
        store.apply(planAction: (action: "set", field: "hotel", data: ["name": "Inn"]))
        #expect(store.selections["activities"] == [["name": "Tower"]])
        #expect(store.contains(field: "hotel", item: ["name": "Inn"]))
        store.apply(planAction: (action: "clear", field: "all", data: .null))
        #expect(store.selections == Selections.empty)
    }

    @Test func test_saveCreatesThenUpdates() async throws {
        let plans = FakePlansRepository()
        plans.onCreate.handler = { new in SavedPlan(id: 7, name: new.name, searchData: new.searchData, selections: new.selections) }
        plans.onUpdate.handler = { input in SavedPlan(id: input.id, name: input.update.name ?? "Lisbon trip") }
        let store = CurrentPlanStore(files: MemoryFileStore())
        store.searchData = ["destination": "Lisbon", "departure_date": "2026-05-01"]
        store.toggle(field: "hotel", item: ["name": "Inn"])

        let created = try await store.save(name: "Lisbon trip", using: plans)
        #expect(created.id == 7)
        #expect(plans.onCreate.callCount == 1)
        #expect(plans.onCreate.lastCall?.name == "Lisbon trip")
        #expect(plans.onCreate.lastCall?.searchData["destination"] == "Lisbon")
        #expect(store.savedPlanID == 7)
        #expect(!store.isDirty)

        store.toggle(field: "activities", item: ["name": "Tram 28"])
        #expect(store.isDirty)
        _ = try await store.save(name: nil, using: plans)
        #expect(plans.onCreate.callCount == 1)
        #expect(plans.onUpdate.callCount == 1)
        #expect(plans.onUpdate.lastCall?.id == 7)
        #expect(plans.onUpdate.lastCall?.update.name == nil)
        #expect(plans.onUpdate.lastCall?.update.selections?["activities"] == [["name": "Tram 28"]])
        #expect(!store.isDirty)
    }

    @Test func test_saveSnapshotsItinerary() async throws {
        let plans = FakePlansRepository()
        plans.onCreate.handler = { new in SavedPlan(id: 1, name: new.name, selections: new.selections) }
        let store = CurrentPlanStore(files: MemoryFileStore())
        let days: JSONValue = [["day": 1, "morning": ["activity": "Castle"]], ["day": 2, "morning": ["activity": "Beach"]]]
        store.latestResults = ["itinerary": ["days": days, "total_estimated_cost_usd": 420, "summary": "x"]]
        store.toggle(field: "activities", item: ["name": "Castle", "link_verified": true, "link_checked": true])
        var selections = store.selections
        if case .object(var object) = selections {
            object["itinerary_layout"] = ["fp": "abc", "moves": [:]]
            selections = .object(object)
        }
        store.selections = selections

        _ = try await store.save(name: "Trip", using: plans)
        let sent = try #require(plans.onCreate.lastCall?.selections)
        // The itinerary as generated (readers arrange it with the overlay sent alongside), like the web.
        #expect(sent["itinerary"] == ["days": days, "total_estimated_cost_usd": 420])
        #expect(sent["itinerary_layout"] == ["fp": "abc", "moves": [:]])
        #expect(sent["activities"] == [["name": "Castle"]])
        // The on-screen selections keep their evidence and get no snapshot.
        #expect(store.selections["itinerary"].isNull)

        // A loaded saved plan keeps its own snapshot; the old results are not attached to it.
        store.load(SavedPlan(id: 9, name: "Old", selections: ["itinerary": ["days": [["day": 1]]]]))
        plans.onUpdate.handler = { input in SavedPlan(id: input.id, name: "Old", selections: input.update.selections ?? .null) }
        _ = try await store.save(name: nil, using: plans)
        #expect(plans.onUpdate.lastCall?.update.selections?["itinerary"] == ["days": [["day": 1]]])
    }

    @Test func test_persistsAndRestores() async throws {
        let files = MemoryFileStore()
        let first = CurrentPlanStore(files: files)
        first.searchData = ["destination": "Kyoto"]
        first.toggle(field: "activities", item: ["name": "Fushimi Inari"])
        first.savedPlanID = 4
        #expect(files.writes.isEmpty) // debounced
        await first.flushPersistence()
        #expect(files.writes == [CurrentPlanStore.fileName])

        let second = CurrentPlanStore(files: files)
        #expect(second.selections == Selections.empty)
        #expect(files.reads.isEmpty)
        await second.restore()
        #expect(second.selections == first.selections)
        #expect(second.searchData == ["destination": "Kyoto"])
        #expect(second.savedPlanID == 4)
        #expect(second.isDirty)

        // The debounce writes on its own after the delay.
        let quick = CurrentPlanStore(files: files, persistDelay: .milliseconds(20))
        quick.reset()
        #expect(await waitUntil { files.writes.count == 2 })
    }

    @Test func test_perUserIsolation() async throws {
        let files = MemoryFileStore()
        let store = CurrentPlanStore(files: files)
        await store.switchUser("amy")
        store.searchData = ["destination": "Kyoto"]
        store.toggle(field: "activities", item: ["name": "Fushimi Inari"])
        store.savedPlanID = 4
        store.planName = "Kyoto trip"

        // Bob signs in on the same device: nothing of Amy's is shown, and a save creates his own plan.
        await store.switchUser("bob")
        #expect(store.selections == Selections.empty)
        #expect(store.searchData == nil)
        #expect(store.savedPlanID == nil)
        #expect(store.planName == nil)
        #expect(!store.isDirty)
        store.toggle(field: "hotel", item: ["name": "Inn"])
        await store.flushPersistence()

        // Amy's plan was written to her own file before the switch, and comes back for her only.
        await store.switchUser("amy")
        #expect(store.savedPlanID == 4)
        #expect(store.searchData == ["destination": "Kyoto"])
        #expect(store.selections["hotel"].isNull || store.selections["hotel"] == Selections.empty["hotel"])
        #expect(Set(files.files.keys) == [CurrentPlanStore.path(for: "amy"), CurrentPlanStore.path(for: "bob")])
        #expect(!CurrentPlanStore.path(for: "amy").contains("amy"))

        // Signed out: the guest file, not Amy's plan.
        await store.switchUser(nil)
        #expect(store.savedPlanID == nil)
        #expect(store.selections == Selections.empty)
    }

    @Test func test_thrownReadBlocksWritesUntilARetrySucceeds() async throws {
        let seeded = MemoryFileStore()
        let first = CurrentPlanStore(files: seeded)
        first.searchData = ["destination": "Kyoto"]
        first.savedPlanID = 4
        await first.flushPersistence()
        let files = FlakyReadFileStore(MemoryFileStore(files: seeded.files))
        files.failReads = true
        let store = CurrentPlanStore(files: files, persistDelay: .milliseconds(20))
        await store.restore()
        store.toggle(field: "hotel", item: ["name": "Inn"])
        await store.flushPersistence()
        #expect(files.inner.writes.isEmpty)
        files.failReads = false
        #expect(await waitUntil { !files.inner.writes.isEmpty })
        await store.flushPersistence()
        #expect(!files.inner.writes.isEmpty)
    }

    @Test func test_saveResultDroppedWhenUserChangedDuringAwait() async throws {
        let plans = FakePlansRepository()
        let store = CurrentPlanStore(files: MemoryFileStore())
        await store.switchUser("amy")
        store.searchData = ["destination": "Kyoto"]
        plans.onCreate.handler = { new in
            await store.switchUser("bob")
            return SavedPlan(id: 9, name: "Amy trip", searchData: new.searchData, selections: new.selections)
        }
        let saved = try await store.save(name: "Amy trip", using: plans)
        #expect(saved.id == 9)
        #expect(store.username == "bob")
        #expect(store.savedPlanID == nil)
        #expect(store.planName == nil)
    }
}
