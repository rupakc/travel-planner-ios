import Foundation
import Networking
import Telemetry
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureNearby

@MainActor
final class FakeLocation: LocationProviding {
    var access: LocationAccess
    var grantOnRequest: LocationAccess
    var failure: LocationFailure?
    var coordinate = Coordinate(lat: 38.722_252, lng: -9.139_337)
    private(set) var requestCount = 0
    private(set) var readCount = 0

    init(access: LocationAccess = .allowed, grantOnRequest: LocationAccess = .allowed) {
        self.access = access
        self.grantOnRequest = grantOnRequest
    }

    func requestAccess() async -> LocationAccess {
        requestCount += 1
        if access == .notDetermined { access = grantOnRequest }
        return access
    }

    func currentCoordinate() async throws -> Coordinate {
        readCount += 1
        if let failure { throw failure }
        return coordinate
    }
}

@MainActor
private final class Recorder {
    var events: [TelemetryEvent] = []
}

private let v2 = NearbyResponse(
    place: NearbyPlace(name: "Lisbon"),
    sections: [
        NearbySection(
            id: "see", title: "See",
            items: [NearbyItem(name: "Castelo", summary: "Hilltop castle", mapsUri: "https://maps.google.com/?cid=1")]),
        NearbySection(id: "eat", title: "Eat", items: []),
    ],
    attribution: "Google Maps",
    sources: [NearbySource(title: "Maps", uri: "https://maps.google.com")])

@MainActor
private func make(
    location: FakeLocation, fakes: FakeRepositories = FakeRepositories()
) -> (NearbyModel, AppEnvironment, Recorder) {
    let env = AppEnvironment.fake(fakes: fakes)
    let recorder = Recorder()
    return (NearbyModel(env: env, location: location, track: { recorder.events.append($0) }), env, recorder)
}

private func listing(_ url: URL) -> Set<String> {
    let keys: [URLResourceKey] = [.isRegularFileKey]
    guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return [] }
    return Set(walker.compactMap { ($0 as? URL).map { $0.path } }.filter { !$0.contains("telemetry-") })
}

@MainActor
struct NearbyModelTests {
    @Test func test_v2SectionsAndRoundedRequest() async {
        let fakes = FakeRepositories()
        fakes.nearby.onNearby.returns(v2)
        let (model, _, _) = make(location: FakeLocation(), fakes: fakes)
        await model.begin()

        #expect(model.phase == .loaded)
        let sent = fakes.nearby.onNearby.lastCall
        #expect(sent?.sections == true)
        #expect(sent?.lat == 38.722)
        #expect(sent?.lng == -9.139)
        #expect(model.result?.isV2 == true)
        #expect(model.result?.groups.map(\.id) == ["see", "eat"])
        #expect(model.result?.groups[0].rows.first?.mapsURL?.host() == "maps.google.com")
        #expect(model.result?.attribution == "Google Maps")
    }

    @Test func test_v1Fallback() async {
        let fakes = FakeRepositories()
        fakes.nearby.onNearby.returns(
            NearbyResponse(
                place: NearbyPlace(name: "Porto"),
                items: [.object(["name": .string("Ribeira"), "description": .string("Riverside")])]))
        let (model, _, _) = make(location: FakeLocation(), fakes: fakes)
        await model.begin()

        #expect(model.phase == .loaded)
        #expect(model.result?.isV2 == false)
        #expect(model.result?.groups.count == 1)
        #expect(model.result?.groups[0].rows.map(\.name) == ["Ribeira"])
        #expect(model.result?.groups[0].rows[0].mapsURL?.host() == "www.google.com")
    }

    @Test func test_deniedShowsSettings() async {
        let fakes = FakeRepositories()
        let location = FakeLocation(access: .denied)
        let (model, _, _) = make(location: location, fakes: fakes)
        await model.begin()

        #expect(model.phase == .denied)
        #expect(fakes.nearby.onNearby.callCount == 0)
        #expect(location.readCount == 0)
        #if canImport(UIKit)
        #expect(model.settingsURL != nil)
        #endif
    }

    @Test func test_askingAfterExplanationThenDenied() async {
        let fakes = FakeRepositories()
        let location = FakeLocation(access: .notDetermined, grantOnRequest: .denied)
        let (model, _, _) = make(location: location, fakes: fakes)
        await model.begin()
        #expect(model.phase == .intro)
        #expect(location.requestCount == 0)

        await model.useLocation()
        #expect(location.requestCount == 1)
        #expect(model.phase == .denied)
        #expect(fakes.nearby.onNearby.callCount == 0)
    }

    @Test func test_groundingUnavailableShowsBackendText() async {
        let fakes = FakeRepositories()
        fakes.nearby.onNearby.fails(APIError.server(status: 503, detail: "Live map results are off."))
        let (model, _, _) = make(location: FakeLocation(), fakes: fakes)
        await model.begin()
        #expect(model.phase == .failed("Live map results are off."))
    }

    @Test func test_locationTimeoutFails() async {
        let location = FakeLocation()
        location.failure = .timeout
        let fakes = FakeRepositories()
        let (model, _, _) = make(location: location, fakes: fakes)
        await model.begin()
        if case .failed = model.phase {} else { Issue.record("expected failed, got \(model.phase)") }
        #expect(fakes.nearby.onNearby.callCount == 0)
    }

    @Test func test_addToPlanAndMapsTelemetry() async throws {
        let fakes = FakeRepositories()
        fakes.nearby.onNearby.returns(v2)
        let (model, env, recorder) = make(location: FakeLocation(), fakes: fakes)
        await model.begin()
        let row = try #require(model.result?.groups.first?.rows.first)

        #expect(!model.isInPlan(row))
        model.togglePlan(row)
        #expect(model.isInPlan(row))
        #expect((env.plan.selections["places_to_see"].array ?? []).count == 1)
        model.togglePlan(row)
        #expect(!model.isInPlan(row))

        model.didOpenMaps(row)
        let linked = recorder.events.contains { event in
            if case .linkOut(let section, let domain) = event { return section == "nearby" && domain == "maps.google.com" }
            return false
        }
        #expect(linked)
    }

    @Test func test_neverPersisted() async throws {
        let roots = [URL.applicationSupportDirectory, FileManager.default.temporaryDirectory, URL.documentsDirectory]
        let before = roots.map(listing)
        let fakes = FakeRepositories()
        fakes.nearby.onNearby.returns(v2)
        let (model, _, _) = make(location: FakeLocation(), fakes: fakes)
        await model.begin()
        let row = try #require(model.result?.groups.first?.rows.first)
        model.togglePlan(row)
        try? await Task.sleep(for: .milliseconds(1300))  // past the plan store's write debounce

        #expect(model.result?.count == 1)
        #expect(roots.map(listing) == before)
    }
}
