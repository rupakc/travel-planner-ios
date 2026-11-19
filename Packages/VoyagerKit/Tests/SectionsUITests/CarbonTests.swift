import Domain
import Foundation
import L10n
import Testing
import TestFixtures
import VoyagerModel

@testable import SectionsUI

/// Records the bodies the card asked for and answers with a scripted result.
@MainActor
private final class CarbonLoader {
    var bodies: [JSONValue] = []
    var answer: CarbonFetch

    init(_ answer: CarbonFetch) { self.answer = answer }

    func load(_ body: JSONValue) async -> CarbonFetch {
        bodies.append(body)
        return answer
    }
}

@MainActor
struct CarbonModelTests {
    private static func report() throws -> CarbonReport {
        let json = try JSONDecoder().decode(JSONValue.self, from: try Fixtures.data("json/carbon_trip.json"))
        return try #require(CarbonReport(json: json))
    }

    private static func defaults() -> UserDefaults {
        let name = "carbon-tests-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name) ?? .standard
        store.removePersistentDomain(forName: name)
        return store
    }

    private static func model(_ loader: CarbonLoader, defaults: UserDefaults = defaults()) -> CarbonFootprintModel {
        CarbonFootprintModel(defaults: defaults, debounce: .milliseconds(1)) { body in await loader.load(body) }
    }

    private static func settle(_ model: CarbonFootprintModel) async {
        for _ in 0..<200 where model.phase == .loading || model.refreshing {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func test_loadsAndShowsTheReport() async throws {
        let loader = CarbonLoader(.loaded(try Self.report()))
        let model = Self.model(loader)
        #expect(model.phase == .idle)
        model.request(["diet": "mixed"])
        #expect(model.phase == .loading)
        await Self.settle(model)
        #expect(model.phase == .loaded)
        #expect(model.report?.totalKg == 1000)
        #expect(loader.bodies == [["diet": "mixed"]])
    }

    @Test func test_sameBodyIsNotAskedTwice() async throws {
        let loader = CarbonLoader(.loaded(try Self.report()))
        let model = Self.model(loader)
        model.request(["diet": "mixed"])
        await Self.settle(model)
        model.request(["diet": "mixed"])
        await Self.settle(model)
        #expect(loader.bodies.count == 1)
    }

    @Test func test_aNewerRequestSupersedesTheOlderOne() async throws {
        let loader = CarbonLoader(.loaded(try Self.report()))
        let model = CarbonFootprintModel(defaults: Self.defaults(), debounce: .milliseconds(30)) { body in await loader.load(body) }
        model.request(["diet": "mixed"])
        model.request(["diet": "vegan"])
        await Self.settle(model)
        #expect(loader.bodies == [["diet": "vegan"]])
    }

    @Test func test_refreshKeepsTheLastAnswerOnScreen() async throws {
        let loader = CarbonLoader(.loaded(try Self.report()))
        let model = Self.model(loader)
        model.request(["diet": "mixed"])
        await Self.settle(model)
        model.request(["diet": "vegan"])
        #expect(model.phase == .loaded)
        #expect(model.refreshing)
        #expect(model.report != nil)
        await Self.settle(model)
        #expect(!model.refreshing)
    }

    @Test func test_404HidesTheCardForGood() async throws {
        let loader = CarbonLoader(.gone)
        let model = Self.model(loader)
        model.request(["diet": "mixed"])
        await Self.settle(model)
        #expect(model.phase == .gone)
        model.request(["diet": "vegan"])
        await Self.settle(model)
        #expect(loader.bodies.count == 1)
    }

    @Test func test_failureSaysUnavailable() async {
        let model = Self.model(CarbonLoader(.failed))
        model.request(["diet": "mixed"])
        await Self.settle(model)
        #expect(model.phase == .failed)
        #expect(model.report == nil)
    }

    @Test func test_cancelDropsAPendingRequestAndAsksAgainLater() async throws {
        let loader = CarbonLoader(.loaded(try Self.report()))
        let model = CarbonFootprintModel(defaults: Self.defaults(), debounce: .milliseconds(200)) { body in await loader.load(body) }
        model.request(["diet": "mixed"])
        model.cancel()  // left the screen inside the debounce
        try await Task.sleep(for: .milliseconds(300))
        #expect(loader.bodies.isEmpty)
        model.request(["diet": "mixed"])  // back on screen: the same body is asked again
        await Self.settle(model)
        #expect(loader.bodies == [["diet": "mixed"]])
        #expect(model.phase == .loaded)
    }

    @Test func test_cancelAfterAnAnswerKeepsItAndAsksNothing() async throws {
        let loader = CarbonLoader(.loaded(try Self.report()))
        let model = Self.model(loader)
        model.request(["diet": "mixed"])
        await Self.settle(model)
        model.cancel()
        model.request(["diet": "mixed"])
        await Self.settle(model)
        #expect(loader.bodies.count == 1)
        #expect(model.phase == .loaded && model.report != nil)
    }

    @Test func test_dietIsRememberedAndValidated() {
        let store = Self.defaults()
        let first = Self.model(CarbonLoader(.failed), defaults: store)
        #expect(first.diet == "mixed")
        first.setDiet("vegan")
        first.setDiet("keto")
        #expect(first.diet == "vegan")
        #expect(store.string(forKey: CarbonFootprintModel.dietKey) == "vegan")
        #expect(Self.model(CarbonLoader(.failed), defaults: store).diet == "vegan")
        store.set("carnivore", forKey: CarbonFootprintModel.dietKey)
        #expect(Self.model(CarbonLoader(.failed), defaults: store).diet == "mixed")
    }
}

struct CarbonTextTests {
    private static func report() throws -> CarbonReport {
        let json = try JSONDecoder().decode(JSONValue.self, from: try Fixtures.data("json/carbon_trip.json"))
        return try #require(CarbonReport(json: json))
    }

    @Test func test_linesAreTranslatedFromKindAndParams() throws {
        let lines = try Self.report().lines
        LanguageController.withLanguage(.en) {
            #expect(CarbonText.line(lines[0]) == "Flight LHR–CDG")
            #expect(CarbonText.line(lines[1]) == "Stay in Paris: nights 4, rooms 1")
            #expect(CarbonText.line(lines[2]) == "Paris–Lyon by train (470.4 km)")
            #expect(CarbonText.line(lines[3]) == "Meals (Mixed diet): days 4, travellers 2")
            // An unknown kind shows the backend's own text.
            #expect(CarbonText.line(lines[4]) == "Zeppelin ride")
        }
    }

    @Test func test_assumptionsAreTranslatedFromCode() throws {
        let assumptions = try Self.report().assumptions
        LanguageController.withLanguage(.en) {
            #expect(CarbonText.assumption(assumptions[0]) == "Rooms: 1 (one per two travellers).")
            #expect(CarbonText.assumption(assumptions[1]) == "Cabin: economy.")
            #expect(CarbonText.assumption(assumptions[2]) == "Something new.")
        }
    }

    @Test func test_otherLanguagesUseTheirCatalogue() throws {
        let line = try Self.report().lines[1]
        let german = LanguageController.withLanguage(.de) { CarbonText.line(line) }
        let english = LanguageController.withLanguage(.en) { CarbonText.line(line) }
        #expect(german != english)
        #expect(german.contains("Paris"))
    }

    @Test func test_kilogramFormatting() {
        LanguageController.withLanguage(.en) {
            #expect(CarbonText.kg0(1000.4) == "1,000")
            #expect(CarbonText.kg1(4.25) == "4.3")
            #expect(CarbonText.kg1(4.0) == "4")
            #expect(CarbonText.kg1(12.6) == "13")
        }
    }

    @Test func test_methodAndCategoryNames() {
        LanguageController.withLanguage(.en) {
            #expect(CarbonText.method("measured_tim") == "Google TIM")
            #expect(CarbonText.method("estimate") == "Estimate")
            #expect(CarbonText.category("ground") == "Getting around")
            #expect(CarbonText.diet("meat_heavy") == "Lots of meat")
        }
    }

    @Test func test_sourceDateHasTheYear() {
        let text = LanguageController.withLanguage(.en) { CarbonText.day("2027-06-12") }
        #expect(text?.contains("2027") == true)
        #expect(CarbonText.day("soon") == nil)
        #expect(CarbonText.day(nil) == nil)
    }
}

@MainActor
struct EmissionsChipTests {
    private static let emissions: JSONValue = [
        "kg_co2e_per_pax": 134,
        "cabin": "economy",
        "by_class": ["economy": 134, "premiumEconomy": 134, "business": 201, "first": 201],
        "source": "Google Travel Impact Model",
        "attribution_url": "https://travelimpactmodel.org",
    ]

    @Test func test_nothingWithoutAUsableFigure() {
        #expect(EmissionsChip.content(.null) == nil)
        #expect(EmissionsChip.content(["kg_co2e_per_pax": "n/a"]) == nil)
        #expect(EmissionsChip.content(["by_class": ["economy": 10]]) == nil)
    }

    @Test func test_chipAndClassBreakdown() throws {
        let content = try #require(LanguageController.withLanguage(.en) { EmissionsChip.content(Self.emissions) })
        #expect(content.chip == "≈ 134 kg CO₂e")
        #expect(content.classLines == ["Economy: 134 kg", "Premium economy: 134 kg", "Business: 201 kg", "First: 201 kg"])
        #expect(content.url.absoluteString == "https://travelimpactmodel.org")
    }

    @Test func test_onlyHttpsAttributionLinks() throws {
        let content = try #require(EmissionsChip.content(["kg_co2e_per_pax": 5, "attribution_url": "javascript:alert(1)"]))
        #expect(content.url.absoluteString == "https://travelimpactmodel.org")
        #expect(content.classLines.isEmpty)
    }
}
