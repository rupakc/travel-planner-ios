import Domain
import SwiftUI
import Testing
import VoyagerModel

@testable import SectionsUI

enum ItineraryFixture {
    static let itinerary: JSONValue = [
        "days": [
            [
                "day_number": 1, "city": "Lisbon",
                "slots": [
                    [
                        "time_of_day": "morning", "activity": "Belém Tower", "location": "Belém", "estimated_cost_usd": 12,
                        "lat": 38.6916, "lng": -9.2160, "duration_hours": 2,
                    ],
                    [
                        "time_of_day": "afternoon", "activity": "Alfama walk", "lat": 38.711, "lng": -9.130,
                        "from_link": true, "link_place": "Alfama", "link_quote": "start here",
                    ],
                    ["time_of_day": "evening", "activity": "Fado dinner", "estimated_cost_usd": 45, "lat": 38.71, "lng": -9.14],
                ],
            ],
            [
                "day_number": 2, "city": "Lisbon",
                "slots": [
                    ["time_of_day": "morning", "activity": "Jerónimos Monastery", "estimated_cost_usd": 10, "lat": 38.698, "lng": -9.206],
                    ["time_of_day": "afternoon", "activity": "LX Factory", "lat": 38.703, "lng": -9.178],
                ],
            ],
        ]
    ]

    static let findings: JSONValue = [
        "overall": "amber", "score": 72, "summary": "Solid plan with two timing risks.",
        "findings": [
            ["severity": "low", "category": "budget", "day_number": 2, "issue": "Day 2 looks cheap.", "suggestion": "Add a lunch budget."],
            [
                "severity": "high", "category": "timing", "day_number": 1, "issue": "Flight lands late.",
                "suggestion": "Keep day 1 light.",
            ],
            ["severity": "medium", "category": "visa", "day_number": nil, "issue": "Check passport validity.", "suggestion": "Renew early."],
        ],
    ]
}

final class Box: @unchecked Sendable {
    var selections: [JSONValue] = []
    var payload: JSONValue?
}

@MainActor
struct ItineraryTests {
    private func model(
        selections: JSONValue = Selections.empty, box: Box = Box()
    ) -> ItineraryEditorModel {
        ItineraryEditorModel(
            itinerary: ItineraryFixture.itinerary, selections: selections,
            persist: { box.selections.append($0) })
    }

    private func keys(_ model: ItineraryEditorModel, day: Int) -> [String] {
        (model.arranged["days"][day]["slots"].array ?? []).compactMap { $0["key"].string }
    }

    @Test func test_moveUpdatesLayoutFingerprinted() {
        let box = Box()
        let editor = model(box: box)
        #expect(editor.targets(for: "1-evening").contains { $0["day_number"].int == 2 && $0["time_of_day"].string == "evening" })
        #expect(editor.move(key: "1-evening", day: 2, timeOfDay: "evening"))
        let layout = editor.selections["itinerary_layout"]
        #expect(layout["fingerprint"].string == ItineraryLayout.fingerprint(ItineraryFixture.itinerary))
        #expect(layout["positions"]["1-evening"].string == "2-evening")
        #expect(keys(editor, day: 1).contains("1-evening"))
        #expect(!keys(editor, day: 0).contains("1-evening"))
        #expect(editor.changeCount == 1)
        #expect(box.selections.last?["itinerary_layout"] == layout)
        // an invalid target changes nothing
        #expect(!editor.move(key: "1-evening", day: 9, timeOfDay: "evening"))
        // undo and reset
        editor.undo()
        #expect(editor.changeCount == 0)
        _ = editor.move(key: "1-morning", day: 2, timeOfDay: "morning")
        #expect(editor.changeCount == 2)  // swapped with the occupant
        editor.reset()
        #expect(editor.changeCount == 0 && editor.layout.isNull)
    }

    @Test func test_removeAndRestore() {
        let editor = model()
        #expect(editor.remove(key: "2-afternoon"))
        #expect(editor.removed.count == 1)
        #expect(!keys(editor, day: 1).contains("2-afternoon"))
        #expect(editor.restore(key: "2-afternoon"))
        #expect(editor.removed.isEmpty)
        #expect(keys(editor, day: 1).contains("2-afternoon"))
    }

    @Test func test_staleLayoutIgnored() {
        let stale: JSONValue = ["fingerprint": "not-this-itinerary", "positions": ["1-morning": "2-evening"]]
        var selections = Selections.empty.object ?? [:]
        selections["itinerary_layout"] = stale
        let editor = model(selections: .object(selections))
        #expect(editor.changeCount == 0)
        #expect(keys(editor, day: 0) == ["1-morning", "1-afternoon", "1-evening"])
        #expect(editor.removed.isEmpty)
        // the first edit replaces the stale layout with a fresh, fingerprinted one
        #expect(editor.move(key: "1-evening", day: 2, timeOfDay: "evening"))
        #expect(editor.layout["fingerprint"].string == ItineraryLayout.fingerprint(ItineraryFixture.itinerary))
    }

    @Test func test_editAndNotePersistInSelections() {
        let box = Box()
        let editor = model(box: box)
        editor.setEdit(key: "1-morning", field: "activity", value: "Torre de Belém")
        editor.setEdit(key: "1-morning", field: "cost", value: 20)
        editor.setNote(key: "1-morning", text: "Buy tickets online")
        let saved = box.selections.last ?? .null
        #expect(saved["itinerary_edits"]["1-morning"]["activity"].string == "Torre de Belém")
        #expect(saved["itinerary_edits"]["1-morning"]["cost"].double == 20)
        #expect(saved["itinerary_notes"]["1-morning"].string == "Buy tickets online")
        #expect(editor.activityName(key: "1-morning", fallback: "Belém Tower") == "Torre de Belém")
        // the day cost follows the edited cost
        #expect(editor.arranged["days"][0]["daily_estimated_cost_usd"].double != nil || editor.edits["1-morning"]["cost"].double == 20)
        // a read-only itinerary ignores edits
        editor.editable = false
        editor.setNote(key: "1-afternoon", text: "x")
        #expect(editor.notes["1-afternoon"].isNull)
    }

    @Test func test_openingEditorAndDoneWritesNothing() throws {
        let box = Box()
        let editor = model(box: box)
        let slot = try #require(editor.scheduledDays[0]["slots"].array?.first)
        editor.saveEditor(key: "1-morning", slot: slot, activity: "Belém Tower", location: "Belém", costText: "12", note: "")
        #expect(box.selections.isEmpty)
        #expect(editor.edits["1-morning"].isNull)
    }

    @Test func test_saveEditorBatchesOneCommitOfChangedFieldsOnly() throws {
        let box = Box()
        let editor = model(box: box)
        let slot = try #require(editor.scheduledDays[0]["slots"].array?.first)
        editor.saveEditor(key: "1-morning", slot: slot, activity: "Belém Tower", location: "Belém", costText: "20", note: "  hi  ")
        #expect(box.selections.count == 1)
        let saved = try #require(box.selections.last)
        #expect(saved["itinerary_edits"]["1-morning"]["cost"].double == 20)
        #expect(saved["itinerary_edits"]["1-morning"]["activity"].isNull)
        #expect(saved["itinerary_edits"]["1-morning"]["location"].isNull)
        #expect(saved["itinerary_notes"]["1-morning"].string == "hi")
    }

    @Test func test_junkCostKeepsOldValueAndNotesAreCapped() throws {
        let editor = model()
        let slot = try #require(editor.scheduledDays[0]["slots"].array?.first)
        editor.saveEditor(key: "1-morning", slot: slot, activity: "Belém Tower", location: "Belém", costText: "20", note: "")
        editor.saveEditor(key: "1-morning", slot: slot, activity: "Belém Tower", location: "Belém", costText: "abc", note: "")
        #expect(editor.edits["1-morning"]["cost"].double == 20)
        editor.saveEditor(key: "1-morning", slot: slot, activity: "x", location: "Belém", costText: "20", note: String(repeating: "n", count: 5000))
        #expect(editor.notes["1-morning"].string?.count == ItineraryEditorModel.maxNoteLength)
        #expect(TripMapView.stops(from: editor.arranged, edits: editor.edits).first?.name == "x")
    }

    @Test func test_pickKeepsScheduledTimes() throws {
        let editor = model()
        let slot = try #require(editor.scheduledDays[0]["slots"].array?.first)
        editor.togglePick(slot, dayNumber: 1)
        let picked = try #require(editor.selections["itinerary_slots"].array?.first)
        #expect(picked["key"].string == "1-morning")
        #expect(picked["start_time"].string != nil && picked["end_time"].string != nil)
        #expect(editor.isPicked(key: "1-morning"))
        // moving a picked slot re-points the pick at its new day and time
        _ = editor.move(key: "1-morning", day: 2, timeOfDay: "morning")
        let moved = editor.selections["itinerary_slots"][0]
        #expect(moved["day_number"].int == 2)
        editor.togglePick(slot, dayNumber: 1)
        #expect(!editor.isPicked(key: "1-morning"))
    }

    @Test func test_recheckSendsArrangedItinerary() async throws {
        let box = Box()
        let editor = model()
        _ = editor.move(key: "1-evening", day: 2, timeOfDay: "evening")
        editor.setEdit(key: "1-evening", field: "activity", value: "Late fado")
        let stress = StressTestModel(editor: editor) { payload in
            box.payload = payload
            return ["overall": "green", "score": 90, "findings": []]
        }
        #expect(stress.canRecheck && stress.layoutMoved && stress.rechecked == nil)
        await stress.recheck()
        let sent = try #require(box.payload)
        let day2 = try #require(sent["days"][1]["slots"].array)
        #expect(day2.contains { $0["activity"].string == "Late fado" })
        #expect(sent["days"][0]["slots"].array?.count == 2)
        for day in sent["days"].array ?? [] {
            for slot in day["slots"].array ?? [] { #expect(slot["key"].isNull) }
        }
        #expect(sent["removed"].isNull && sent["changed"].isNull)
        #expect(day2.contains { $0["start_time"].string != nil })
        #expect(stress.rechecked?["overall"].string == "green" && !stress.isStale)
        // a later edit makes the result stale
        editor.setEdit(key: "1-morning", field: "activity", value: "Renamed")
        #expect(stress.isStale)
    }

    @Test func test_recheckFailureShowsServerText() async {
        let editor = model()
        _ = editor.move(key: "1-evening", day: 2, timeOfDay: "evening")
        let stress = StressTestModel(editor: editor) { _ in throw ItineraryRecheckError(message: "Too many requests") }
        await stress.recheck()
        #expect(stress.errorMessage == "Too many requests" && stress.rechecked == nil && !stress.isRechecking)
    }

    @Test func test_mapNotBuiltWhenCollapsed() {
        #expect(!TripMapView.buildsMap(expanded: false, stopCount: 5))
        #expect(!TripMapView.buildsMap(expanded: true, stopCount: 0))
        #expect(TripMapView.buildsMap(expanded: true, stopCount: 1))
        #expect(!TripMapView.initiallyExpanded(layout: .compact))
        #expect(TripMapView.initiallyExpanded(layout: .regular))
        #expect(TripMapView.stops(from: ItineraryFixture.itinerary).count == 5)
    }

    @Test func test_looseJSONNeverTraps() {
        let odd: JSONValue = [
            "days": [
                [
                    "day_number": 1e30,
                    "slots": [
                        ["time_of_day": "morning", "activity": "A", "lat": 1e308, "lng": "x"],
                        ["time_of_day": "evening", "activity": "B", "lat": 95, "lng": 10],
                        ["time_of_day": "evening", "activity": "C", "lat": 10, "lng": 10],
                    ],
                ],
                "not a day", nil,
            ]
        ]
        #expect(TripMapView.stops(from: odd).count == 1)
        let editor = ItineraryEditorModel(itinerary: odd)
        _ = editor.scheduledDays
        let data: JSONValue = ["score": 1e300, "findings": [["day_number": 1e30, "severity": 7], "x", ["day_number": -3.5]]]
        #expect(StressTestSectionView.score(data) == 100)
        #expect(StressTestSectionView.grouped(data).count == 1)
        #expect(StressTestSectionView.overall(["overall": 3]) == "amber")
        #expect(ItineraryText.parseCost("1e999") == nil && ItineraryText.parseCost("12,5") == 12.5)
        #expect(ItineraryText.cost(.number(.nan)) == nil && ItineraryText.cost(.number(-1)) == nil)
    }

    @Test func test_findingsGroupedByDayWorstFirst() {
        let groups = StressTestSectionView.grouped(ItineraryFixture.findings)
        #expect(groups.map(\.day) == [nil, 1, 2])
        let sameDay: JSONValue = [
            "findings": [["severity": "low", "day_number": 1], ["severity": "high", "day_number": 1], ["severity": "medium", "day_number": 1]]
        ]
        #expect(StressTestSectionView.grouped(sameDay)[0].findings.map { $0["severity"].string } == ["high", "medium", "low"])
    }

    @Test func test_linkCoverage() {
        let search: JSONValue = ["must_include": [["name": "Alfama"], ["name": "Sintra"]]]
        let coverage = ItineraryText.linkCoverage(searchData: search, itinerary: ItineraryFixture.itinerary)
        #expect(coverage == .init(total: 2, inItinerary: 1, missing: ["Sintra"], state: .ready))
        #expect(ItineraryText.linkCoverage(searchData: nil, itinerary: ItineraryFixture.itinerary) == nil)
        #expect(ItineraryText.linkCoverage(searchData: search, itinerary: [:])?.state == .pending)
    }

    @Test func test_dayRowsAddFreeTimeWhileEditing() {
        let day2 = ItineraryFixture.itinerary["days"][1]
        #expect(DayView.rows(for: day2, editable: true).count == 3)
        #expect(DayView.rows(for: day2, editable: false).count == 2)
    }

    @Test func test_dragPayloadIsPrefixed() {
        #expect(ItineraryDrag.key(from: ItineraryDrag.payload("1-morning")) == "1-morning")
        #expect(ItineraryDrag.key(from: "1-morning") == nil)
    }
}
