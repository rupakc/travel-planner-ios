import Foundation
import Testing
import TestFixtures
import VoyagerModel
@testable import Domain

@Suite struct PlaceFactsTests {
    private func section() throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: try Fixtures.data("json/place_facts.json"))
    }

    private func berlin() throws -> PlaceFacts.Place {
        try #require(PlaceFacts.places(try section()).first)
    }

    // MARK: - Section

    @Test func hidesWithoutFacts() {
        let empty: JSONValue = ["historical": [], "fun": [], "popular": [], "unbelievable": [], "little_known": []]
        let cases: [JSONValue?] = [
            nil, .null, ["error": "x"], ["places": []], ["places": [["key": "k", "groups": empty]]], "text",
            ["places": [["key": "k", "groups": ["fun": [["text": " "]]]]]],
        ]
        for data in cases {
            #expect(!PlaceFacts.hasFacts(data))
            #expect(PlaceFacts.places(data).isEmpty)
        }
    }

    @Test func dropsPlacesWithoutFactsAndKeepsTheFiveGroups() throws {
        let places = PlaceFacts.places(try section())
        #expect(places.map(\.key) == ["city:2950159", "country:DE"])
        #expect(places[0].name == "Berlin" && places[0].scope == "city")
        #expect(Set(places[0].groups.keys) == Set(PlaceFacts.factTypes))
        #expect(places[0].availableTypes == ["historical", "fun", "popular", "unbelievable"])
        #expect(places[1].availableTypes == ["popular"])
    }

    @Test func dropsFactsWithoutText() throws {
        let facts = try berlin().groups["unbelievable"] ?? []
        #expect(facts.map(\.id) == ["a:1"])
    }

    @Test func crawlerFactKeepsItsCitation() throws {
        let fact = try #require(try berlin().groups["historical"]?.first)
        #expect(fact.isCrawler && !fact.isAI)
        #expect(fact.lang == "en")
        let citation = try #require(fact.citation)
        #expect(citation.name == "Wikidata")
        #expect(citation.url?.absoluteString == "https://www.wikidata.org/wiki/Q64#P571")
        #expect(citation.asOf == "2026-11-20")
        #expect(citation.attribution == "Wikidata (CC0 1.0)")
        #expect(citation.licenceURL?.absoluteString == "https://creativecommons.org/publicdomain/zero/1.0/")
        #expect(!citation.conflict)
    }

    @Test func linksAreHttpsOnly() throws {
        let fact = try #require(try berlin().groups["popular"]?.first)
        let citation = try #require(fact.citation)
        #expect(citation.url == nil, "javascript: is never linked")
        #expect(citation.licenceURL == nil, "plain http is never linked")
        #expect(citation.conflict)
        #expect(fact.machineTranslated)
    }

    @Test func aiFactNeverCarriesASource() throws {
        let fact = try #require(try berlin().groups["unbelievable"]?.first)
        #expect(fact.isAI)
        #expect(fact.citation == nil, "a citation the server let through is still not shown")
    }

    @Test func citationFallsBackToSourceIdAndSkipsAPartialDate() throws {
        let places = PlaceFacts.places(try section())
        let citation = try #require(places[1].groups["popular"]?.first?.citation)
        #expect(citation.name == "cia-factbook")
        #expect(citation.asOf == nil)
        #expect(citation.url == nil)
    }

    // MARK: - My Plan

    @Test func selectionHasTheWebShape() throws {
        let place = try berlin()
        let fact = try #require(place.groups["historical"]?.first)
        let item = PlaceFacts.selection(fact, placeName: place.name)
        #expect(item["id"] == "c:1")
        #expect(item["text"] == "Berlin was founded in 1237.")
        #expect(item["fact_type"] == "historical")
        #expect(item["place"] == "Berlin")
        #expect(item["origin"] == "crawler")
        #expect(item["lang"] == "en")
        #expect(item["value_lang"] == .null)
        #expect(item["citation"]["name"] == "Wikidata")
        #expect(item["citation"]["url"] == "https://www.wikidata.org/wiki/Q64#P571")
        #expect(item["citation"]["as_of"] == "2026-11-20T08:00:00Z")
        #expect(item["citation"]["attribution"] == "Wikidata (CC0 1.0)")
        #expect(item["citation"]["licence_url"] == "https://creativecommons.org/publicdomain/zero/1.0/")
        #expect(item["citation"]["publisher"] == .null, "no internal fields")
        #expect(item["citation"]["source_id"] == .null)
    }

    @Test func aiSelectionHasNoCitation() throws {
        let place = try berlin()
        let fact = try #require(place.groups["fun"]?.first)
        let item = PlaceFacts.selection(fact, placeName: place.name)
        #expect(item["origin"] == "ai")
        #expect(item["citation"] == .null)
    }

    @Test func factWithoutIdGetsAStableOne() {
        let fact = PlaceFacts.fact(["text": "Odd fact.", "origin": "ai"], placeKey: "city:1")
        #expect(fact?.id == "city:1:Odd fact.")
    }

    @Test func selectedRoundTrips() throws {
        let place = try berlin()
        let fact = try #require(place.groups["popular"]?.first)
        let back = try #require(PlaceFacts.selected(PlaceFacts.selection(fact, placeName: "Berlin")))
        #expect(back.place == "Berlin")
        #expect(back.fact.text == fact.text)
        #expect(back.fact.valueLang == "de")
        #expect(back.fact.isCrawler)
        #expect(back.fact.citation?.name == "Wikidata")
        #expect(PlaceFacts.selected(["text": ""]) == nil)
        // A plan saved with the old `quote` flag reads as a plain fact with its attribution.
        let legacy: JSONValue = [
            "id": "c:7", "text": "Old fact.", "origin": "crawler", "quote": true,
            "citation": ["name": "Wikipedia", "attribution": "CC BY-SA 4.0"],
        ]
        #expect(PlaceFacts.selected(legacy)?.fact.citation?.attribution == "CC BY-SA 4.0")
    }

    @Test func selectionsToggleByIdAndCount() throws {
        let place = try berlin()
        let first = PlaceFacts.selection(try #require(place.groups["historical"]?.first), placeName: place.name)
        let second = PlaceFacts.selection(try #require(place.groups["fun"]?.first), placeName: place.name)
        var selections = Selections.empty
        selections = Selections.toggle(selections, field: "place_facts", item: first)
        selections = Selections.toggle(selections, field: "place_facts", item: second)
        #expect(Selections.count(selections) == 2)
        #expect(Selections.contains(selections, field: "place_facts", item: first))
        selections = Selections.toggle(selections, field: "place_facts", item: first)
        #expect(!Selections.contains(selections, field: "place_facts", item: first))
        #expect(selections["place_facts"].array?.map { $0["id"] } == ["a:2"])
        #expect(Selections.count(selections) == 1)
    }

    // MARK: - Language tags (`placeFactText.test.js`)

    @Test func langAttrKeepsRealTags() {
        #expect(PlaceFacts.langAttr("de") == "de")
        #expect(PlaceFacts.langAttr("zh-Hant") == "zh-Hant")
        for tag in ["und", "UND", "", "d e", "<x>", String(repeating: "x", count: 40)] {
            #expect(PlaceFacts.langAttr(tag) == nil, "\(tag)")
        }
        #expect(PlaceFacts.langAttr(nil) == nil)
    }

    @Test func splitsTheOneQuotedValue() {
        let parts = PlaceFacts.quotedValue("Berlin’s motto is “Berlin bleibt doch Berlin”.", valueLang: "de")
        #expect(parts == PlaceFacts.QuotedValue(before: "Berlin’s motto is “", value: "Berlin bleibt doch Berlin", after: "”.", lang: "de"))
    }

    @Test func marksNothingWithoutAValueLanguageOrASingleQuotedValue() {
        #expect(PlaceFacts.quotedValue("Motto “A”.", valueLang: nil) == nil)
        #expect(PlaceFacts.quotedValue("Motto “A”.", valueLang: "und") == nil)
        #expect(PlaceFacts.quotedValue("No quotes here.", valueLang: "de") == nil)
        #expect(PlaceFacts.quotedValue("“A” and “B”.", valueLang: "de") == nil)
        #expect(PlaceFacts.quotedValue("Open “only.", valueLang: "de") == nil)
        #expect(PlaceFacts.quotedValue("Empty “ ”.", valueLang: "de") == nil)
    }

    @Test func attributedTextTagsTheTextAndTheValue() throws {
        let fact = try #require(try berlin().groups["popular"]?.first)
        let text = PlaceFacts.attributedText(fact)
        #expect(String(text.characters) == fact.text)
        let runs = text.runs.map { (String(text[$0.range].characters), $0.languageIdentifier) }
        #expect(runs.map(\.0) == ["Berlin’s motto is “", "Berlin bleibt doch Berlin", "”."])
        #expect(runs.map(\.1) == ["en", "de", "en"])
        let plain = try #require(PlaceFacts.fact(["text": "Plain.", "origin": "ai"]))
        #expect(PlaceFacts.attributedText(plain).runs.allSatisfy { $0.languageIdentifier == nil })
    }
}
