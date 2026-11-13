import Foundation
import Networking
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeaturePreferences

@MainActor
struct PreferencesModelTests {
    private let server = Preferences(
        budgetCategory: "high", nationality: "Indian", currentResidence: "Munich, Germany",
        residencePermits: ["Schengen"], existingVisas: ["US"], interests: ["food", "obscure"],
        numTravelers: 4, adults: 2, children: 1, seniors: 0, infants: 1, accessibilityNeeds: ["wheelchair"])

    @Test func test_roundTripPreferences() async {
        var fakes = FakeRepositories()
        fakes.preferences.onGet.returns(server)
        let env = AppEnvironment.fake(fakes: fakes)
        let model = PreferencesModel(env: env, track: { _ in })
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.budget == "high")
        #expect(model.interests == ["food", "obscure"])
        model.toggleInterest("art")
        model.setCount(.children, 2)
        await model.save()
        let sent = fakes.preferences.onPut.lastCall
        #expect(sent?.budgetCategory == "high")
        #expect(sent?.nationality == "Indian")
        #expect(sent?.currentResidence == "Munich, Germany")
        #expect(sent?.residencePermits == ["Schengen"])
        #expect(sent?.existingVisas == ["US"])
        #expect(sent?.interests == ["food", "obscure", "art"])
        #expect(sent?.adults == 2 && sent?.children == 2 && sent?.seniors == 0 && sent?.infants == 1)
        #expect(sent?.numTravelers == 5)
        #expect(sent?.accessibilityNeeds == ["wheelchair"])
        #expect(model.saveStatus == .saved)
    }

    @Test func test_totalTravelersIsAtLeastOne() {
        let model = PreferencesModel(env: AppEnvironment.fake(), track: { _ in })
        model.apply(Preferences(adults: 0, children: 0, seniors: 0, infants: 0))
        #expect(model.draft().numTravelers == 1)
    }

    @Test func test_absurdCountsAreClamped() {
        let model = PreferencesModel(env: AppEnvironment.fake(), track: { _ in })
        model.apply(Preferences(numTravelers: 9_000_000, adults: 9_000_000, children: -5))
        #expect(model.adults == PreferencesModel.maxPerGroup)
        #expect(model.children == 0)
    }

    @Test func test_legacyNumTravelersOnly() {
        let model = PreferencesModel(env: AppEnvironment.fake(), track: { _ in })
        model.apply(Preferences(numTravelers: 3))
        #expect(model.adults == 3)
    }

    @Test func test_saveFailureShowsServerDetail() async {
        var fakes = FakeRepositories()
        fakes.preferences.onGet.returns(server)
        fakes.preferences.onPut.fails(APIError.client(status: 422, detail: "Bad budget", code: nil, body: .null))
        let model = PreferencesModel(env: AppEnvironment.fake(fakes: fakes), track: { _ in })
        await model.load()
        await model.save()
        #expect(model.saveStatus == .failed(detail: "Bad budget"))
        #expect(model.saveFailed)
    }

    @Test func test_loadFailureKeepsFormClosed() async {
        var fakes = FakeRepositories()
        fakes.preferences.onGet.fails(APIError.network)
        let model = PreferencesModel(env: AppEnvironment.fake(fakes: fakes), track: { _ in })
        await model.load()
        #expect(model.phase == .failed)
        await model.save()
        #expect(fakes.preferences.onPut.callCount == 0)
    }

    @Test func test_tagsDedupeAndTrim() {
        let model = PreferencesModel(env: AppEnvironment.fake(), track: { _ in })
        model.addTag("  UK ", to: \.permits)
        model.addTag("UK", to: \.permits)
        model.addTag("   ", to: \.permits)
        #expect(model.permits == ["UK"])
        model.removeTag("UK", from: \.permits)
        #expect(model.permits.isEmpty)
    }
}

@MainActor
struct EmailModelTests {
    private func make(_ configure: (inout FakeRepositories) -> Void = { _ in }) -> (EmailModel, FakeRepositories) {
        var fakes = FakeRepositories()
        configure(&fakes)
        return (EmailModel(env: AppEnvironment.fake(fakes: fakes)), fakes)
    }

    @Test func test_email409Copy() async {
        let (model, _) = make { $0.preferences.onSetEmail.fails(APIError.client(status: 409, detail: "taken", code: nil, body: .null)) }
        model.text = "me@example.com"
        await model.save()
        #expect(model.status == .conflict)
        #expect(model.message.isError)
    }

    @Test func test_email422Copy() async {
        let (model, _) = make { $0.preferences.onSetEmail.fails(APIError.client(status: 422, detail: nil, code: nil, body: .null)) }
        model.text = "me@example.com"
        await model.save()
        #expect(model.status == .invalid)
    }

    @Test func test_invalidAddressNeverSent() async {
        let (model, fakes) = make()
        for bad in ["nope", "a@b", "a b@c.de", "@c.de", "a@.de", "a@b..c"] {
            model.text = bad
            await model.save()
            #expect(model.status == .invalid, "\(bad)")
        }
        #expect(fakes.preferences.onSetEmail.callCount == 0)
    }

    @Test func test_savesAndClears() async {
        let (model, fakes) = make()
        model.text = " Me@Example.com "
        await model.save()
        #expect(fakes.preferences.onSetEmail.lastCall == "Me@Example.com")
        #expect(model.status == .saved)
        model.text = ""
        await model.save()
        #expect(fakes.preferences.onSetEmail.lastCall == "")
        #expect(model.text == "")
    }

    @Test func test_sessionEmailFollowsSave() async {
        let env = AppEnvironment.fake()
        let model = EmailModel(env: env)
        model.text = "new@example.com"
        await model.save()
        #expect(env.auth.session?.user.email == "new@example.com")
        model.text = ""
        await model.save()
        #expect(env.auth.session?.user.email == nil)
    }

    @Test func test_networkFailureIsGeneric() async {
        let (model, _) = make { $0.preferences.onSetEmail.fails(APIError.network) }
        model.text = "me@example.com"
        await model.save()
        #expect(model.status == .failed(detail: nil))
    }
}

@MainActor
struct TasteModelTests {
    private let profile = TasteProfile(
        signals: ["interest": [TasteSignal(value: "food", count: 3)], "zzz": [TasteSignal(value: "x", count: 1)], "pace": []],
        totalSignals: 4)

    @Test func test_resetTasteConfirms() async {
        var fakes = FakeRepositories()
        fakes.preferences.onTaste.returns(profile)
        let model = TasteModel(env: AppEnvironment.fake(fakes: fakes), track: { _ in })
        await model.load()
        model.requestReset()
        #expect(model.confirmingReset)
        #expect(fakes.preferences.onResetTaste.callCount == 0)
        model.cancelReset()
        #expect(fakes.preferences.onResetTaste.callCount == 0)
        model.requestReset()
        fakes.preferences.onTaste.returns(TasteProfile(signals: [:], totalSignals: 0))
        await model.confirmReset()
        #expect(fakes.preferences.onResetTaste.callCount == 1)
        #expect(!model.hasSignals)
    }

    @Test func test_noResetWithoutSignals() async {
        var fakes = FakeRepositories()
        fakes.preferences.onTaste.returns(TasteProfile(signals: [:], totalSignals: 0))
        let model = TasteModel(env: AppEnvironment.fake(fakes: fakes), track: { _ in })
        await model.load()
        model.requestReset()
        #expect(!model.confirmingReset)
    }

    @Test func test_rowsOrderedAndEmptyDropped() async {
        var fakes = FakeRepositories()
        fakes.preferences.onTaste.returns(profile)
        let model = TasteModel(env: AppEnvironment.fake(fakes: fakes), track: { _ in })
        await model.load()
        #expect(model.rows.map(\.type) == ["interest", "zzz"])
    }

    @Test func test_loadFailure() async {
        var fakes = FakeRepositories()
        fakes.preferences.onTaste.fails(APIError.network)
        let model = TasteModel(env: AppEnvironment.fake(fakes: fakes), track: { _ in })
        await model.load()
        #expect(model.phase == .failed)
    }

    @Test func test_resetFailureKeepsProfile() async {
        var fakes = FakeRepositories()
        fakes.preferences.onTaste.returns(profile)
        fakes.preferences.onResetTaste.fails(APIError.network)
        let model = TasteModel(env: AppEnvironment.fake(fakes: fakes), track: { _ in })
        await model.load()
        await model.confirmReset()
        #expect(model.resetFailed)
        #expect(model.hasSignals)
    }
}

struct WrapGeometryTests {
    /// Placing in the width the parent was given must wrap exactly the rows that were measured.
    @Test func test_measuredHeightEqualsPlacedHeight() {
        for scale in [1.0, 1.3, 1.6, 2.4, 3.1] {
            let sizes = (0..<10).map { CGSize(width: (40 + Double($0 * 13 % 47)) * scale, height: 44) }
            for proposal in [90.0, 150, 232, 252, 320, 480, 800] as [CGFloat] {
                let measured = WrapGeometry.measured(sizes: sizes, proposalWidth: proposal, spacing: 8)
                let placed = WrapGeometry.arrange(sizes: sizes, width: measured.width, spacing: 8)
                #expect(placed.size.height == measured.height, "scale \(scale) width \(proposal)")
                #expect(placed.origins.allSatisfy { $0.y + 44 <= measured.height })
            }
        }
    }

    @Test func test_unspecifiedWidthIsOneRowAndEmptyIsZero() {
        let sizes = [CGSize(width: 50, height: 44), CGSize(width: 60, height: 44)]
        #expect(WrapGeometry.measured(sizes: sizes, proposalWidth: nil, spacing: 8) == CGSize(width: 118, height: 44))
        #expect(WrapGeometry.measured(sizes: [], proposalWidth: 100, spacing: 8).height == 0)
    }
}

@MainActor
struct LooseJSONTests {
    @Test func test_hugeAndWrongTypedPreferencesNeverTrap() throws {
        let json = #"{"adults": 1e30, "children": "x", "interests": "food", "num_travelers": -9e99, "budget_category": 7}"#
        let prefs = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        let model = PreferencesModel(env: AppEnvironment.fake(), track: { _ in })
        model.apply(prefs)
        #expect(model.adults >= 0 && model.adults <= PreferencesModel.maxPerGroup)
        #expect(model.draft().numTravelers ?? 0 >= 1)
    }
}
