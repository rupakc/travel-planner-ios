import Domain
import Foundation
import Networking
import SectionsUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeaturePlan

@MainActor
final class MyPlanModelTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_794_484_800)

    private func make(signedIn: Bool = true, filled: Bool = true) -> (MyPlanModel, AppEnvironment, FakeRepositories) {
        let fakes = FakeRepositories()
        let env = PlanFixtures.env(signedIn: signedIn, filled: filled, fakes: fakes)
        let now = fixedNow
        return (MyPlanModel(env: env, now: { now }), env, fakes)
    }

    // MARK: Groups

    func test_groupsCoverEveryPickedField() {
        let (model, _, _) = make()
        XCTAssertEqual(
            model.groups.map(\.id),
            ["flights", "hotel", "activities", "places_to_see", "sim", "tips", "getting_around"])
        XCTAssertEqual(model.groups.first { $0.id == "hotel" }?.entries.first?.title, "Park Hotel Tokyo")
        XCTAssertEqual(model.groups.first { $0.id == "flights" }?.entries.first?.title, "JAL JL5")
        XCTAssertNotNil(model.itinerary)
    }

    func test_removeListItemAndSingleItem() throws {
        let (model, env, _) = make()
        let walk = model.groups.first { $0.id == "activities" }?.entries.first
        XCTAssertEqual(walk?.title, "Tsukiji food walk")
        model.remove(try XCTUnwrap(walk))
        XCTAssertEqual(env.plan.selections["activities"].array?.count, 1)
        XCTAssertEqual(env.plan.selections["activities"][0]["name"].string, "Teamlab Planets")
        XCTAssertTrue(env.plan.isDirty)

        let hotel = model.groups.first { $0.id == "hotel" }?.entries.first
        model.remove(try XCTUnwrap(hotel))
        XCTAssertTrue(env.plan.selections["hotel"].isNull)
        XCTAssertFalse(model.groups.contains { $0.id == "hotel" })
    }

    func test_emptyPlanIsEmpty() {
        let (model, _, _) = make(filled: false)
        XCTAssertTrue(model.isEmpty)
        XCTAssertTrue(model.costParts.isEmpty)
    }

    // MARK: Cost

    func test_costMatchesDomainBreakdownAndBudget() {
        let (model, env, _) = make()
        let expected = PlanCost.total(env.plan.selections, searchData: env.plan.searchData)
        XCTAssertEqual(model.total, expected)
        XCTAssertEqual(Set(model.costParts.map(\.key)), ["hotel", "flights", "activities", "sim"])
        XCTAssertEqual(model.costParts.map(\.amount), model.costParts.map(\.amount).sorted(by: >))
        XCTAssertEqual(model.budget?.isOver, false) // 2,573 of 3,000
        XCTAssertTrue(model.hasUnpricedTransport)
        env.plan.searchData = ["destination": "Tokyo", "budget_usd": 1000]
        XCTAssertEqual(model.budget?.isOver, true)
    }

    // MARK: Save

    func test_saveThenUpdate() async throws {
        let (model, env, fakes) = make()
        fakes.plans.onCreate.returns(SavedPlan(id: 11, name: "Tokyo plan", searchData: PlanFixtures.searchData, selections: PlanFixtures.selections))
        fakes.plans.onUpdate.returns(SavedPlan(id: 11, name: "Renamed", searchData: PlanFixtures.searchData, selections: PlanFixtures.selections))

        env.plan.selections = Selections.toggle(env.plan.selections, field: "tips", item: ["title": "Carry cash"])
        XCTAssertTrue(env.plan.isDirty)
        let first = await model.save(name: "  ")
        XCTAssertTrue(first)
        XCTAssertEqual(fakes.plans.onCreate.callCount, 1)
        // The generated name is random (adjective, noun): check its shape, not a value.
        let created = fakes.plans.onCreate.lastCall?.name ?? ""
        XCTAssertTrue(created.hasPrefix("The ") && created.contains(" Tokyo "), created)
        XCTAssertEqual(env.plan.savedPlanID, 11)
        XCTAssertFalse(env.plan.isDirty)

        let second = await model.save(name: "Renamed")
        XCTAssertTrue(second)
        XCTAssertEqual(fakes.plans.onCreate.callCount, 1)
        XCTAssertEqual(fakes.plans.onUpdate.callCount, 1)
        XCTAssertEqual(fakes.plans.onUpdate.lastCall?.id, 11)
        XCTAssertEqual(fakes.plans.onUpdate.lastCall?.update.name, "Renamed")
        XCTAssertEqual(env.plan.planName, "Renamed")
    }

    func test_saveFailureKeepsDraftAndSaysSo() async {
        let (model, env, fakes) = make()
        fakes.plans.onCreate.fails(APIError.network)
        let saved = await model.save(name: nil)
        XCTAssertFalse(saved)
        XCTAssertNil(env.plan.savedPlanID)
        XCTAssertNotNil(model.toast)
    }

    func test_signedOutCannotSaveOrShare() async {
        let (model, _, fakes) = make(signedIn: false)
        let saved = await model.save(name: nil)
        XCTAssertFalse(saved)
        await model.share()
        XCTAssertEqual(fakes.plans.onCreate.callCount, 0)
        XCTAssertEqual(fakes.plans.onShare.callCount, 0)
        XCTAssertNil(model.shareURL)
        XCTAssertEqual(model.env.recordedRoutes, [.tab(.trips)], "share() while signed out sends the user to sign in")
        model.signIn()
        XCTAssertEqual(model.env.recordedRoutes, [.tab(.trips), .tab(.trips)])
    }

    func test_signedOutDisablesSaveAndShareButNotExport() {
        let (out, _, _) = make(signedIn: false)
        XCTAssertFalse(out.canSave)
        XCTAssertFalse(out.canShare)
        let (signedIn, _, _) = make()
        XCTAssertTrue(signedIn.canSave)
        XCTAssertTrue(signedIn.canShare)
    }

    func test_saveLabelIsSaveUntilThePlanExists() async {
        let (model, env, fakes) = make()
        XCTAssertEqual(model.saveLabel, "Save")
        fakes.plans.onCreate.returns(SavedPlan(id: 11, name: "Tokyo plan", searchData: PlanFixtures.searchData, selections: PlanFixtures.selections))
        env.plan.selections = Selections.toggle(env.plan.selections, field: "tips", item: ["title": "Carry cash"])
        _ = await model.save(name: nil)
        XCTAssertEqual(model.saveLabel, "Save Changes")
    }

    // MARK: Share

    func test_shareURLUsesPublicBase() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "plan-share-\(UUID().uuidString)"))
        let server = ServerEnvironment(
            buildBaseURL: URL(string: "http://127.0.0.1:8001"), trustedHosts: ["voyager.example"], allowsOverride: false,
            defaults: defaults)
        XCTAssertEqual(MyPlanModel.shareURL(token: "abc", base: server.baseURL)?.absoluteString, "http://127.0.0.1:8001/share/abc")
        server.adopt(publicBaseURL: try XCTUnwrap(URL(string: "https://voyager.example")))
        XCTAssertEqual(MyPlanModel.shareURL(token: "abc", base: server.baseURL)?.absoluteString, "https://voyager.example/share/abc")
        // An untrusted host is never adopted.
        server.adopt(publicBaseURL: try XCTUnwrap(URL(string: "https://evil.example")))
        XCTAssertEqual(MyPlanModel.shareURL(token: "abc", base: server.baseURL)?.host, "voyager.example")
        XCTAssertNil(MyPlanModel.shareURL(token: "abc", base: nil))
    }

    func test_shareSavesFirstThenMakesLink() async {
        let (model, env, fakes) = make()
        fakes.plans.onCreate.returns(SavedPlan(id: 11, name: "Tokyo plan", searchData: PlanFixtures.searchData, selections: PlanFixtures.selections))
        fakes.plans.onShare.returns("tok123")
        await model.share()
        XCTAssertEqual(fakes.plans.onCreate.callCount, 1)
        XCTAssertEqual(fakes.plans.onShare.lastCall, 11)
        XCTAssertEqual(model.shareURL?.absoluteString, "https://fake.voyager.test/share/tok123")
        XCTAssertEqual(env.plan.savedPlanID, 11)
    }

    func test_shareFailureShowsMessage() async {
        let (model, env, fakes) = make()
        env.plan.savedPlanID = 5
        env.plan.isDirty = false
        fakes.plans.onShare.fails(APIError.network)
        await model.share()
        XCTAssertNil(model.shareURL)
        XCTAssertNotNil(model.toast)
        XCTAssertEqual(fakes.plans.onCreate.callCount, 0)
    }

    // MARK: Export

    func test_icsFileMatchesDomain() async throws {
        let (model, env, _) = make()
        env.plan.planName = "Tokyo food trip"
        await model.exportCalendar()
        let file = try XCTUnwrap(model.calendarFile)
        XCTAssertEqual(file.pathExtension, "ics")
        XCTAssertEqual(file.lastPathComponent, PlanICS.fileName(planName: "Tokyo food trip", ext: "ics"))
        let written = try String(contentsOf: file, encoding: .utf8)
        let expected = PlanICS.build(
            planName: "Tokyo food trip", searchData: PlanFixtures.searchData, selections: PlanFixtures.selections,
            itinerary: PlanFixtures.itinerary, planID: nil, now: fixedNow, labels: PlanExportLabels.live)
        XCTAssertEqual(written, expected)
        XCTAssertTrue(written.hasPrefix("BEGIN:VCALENDAR\r\n"))
        XCTAssertTrue(written.contains("Senso-ji temple"))
    }

    // MARK: Itinerary editing

    func test_itineraryHostWritesEditsIntoPlanSelections() throws {
        let (model, env, _) = make()
        let host = model.itineraryHost
        XCTAssertTrue(host.editable)
        XCTAssertEqual(host.itinerary()?["days"].array?.count, 2)
        var edited = host.selections()
        edited = Selections.toggle(edited, field: "itinerary_slots", item: ["key": "1-morning", "day_number": 1])
        host.setSelections(edited)
        XCTAssertEqual(env.plan.selections["itinerary_slots"].array?.count, 1)
        XCTAssertTrue(env.plan.isDirty)
        XCTAssertNotNil(host.recheck)
    }
}
