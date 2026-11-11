import DesignSystem
import Foundation
import Testing
import VoyagerModel

@testable import SharedUI

struct VerificationBadgeModelTests {
    private func model(_ level: String?, pending: Bool? = nil) throws -> VerificationBadgeModel {
        var object: [String: JSONValue] = ["label": .string("Backend label")]
        if let level { object["level"] = .string(level) }
        if let pending { object["pending"] = .bool(pending) }
        return try #require(VerificationBadgeModel(.object(object)))
    }

    @Test func test_levelSelectsColourFamily() throws {
        #expect(try model("verified").family == .emerald)
        #expect(try model("partial").family == .amber)
        #expect(try model("unverified").family == .gray)
        #expect(try model("conflict").family == .red)
    }

    @Test func test_unknownLevelFallsBackToUnverified() throws {
        let unknown = try model("holographic")
        #expect(unknown.level == .unverified)
        #expect(unknown.family == .gray)
        #expect(try model(nil).level == .unverified)
    }

    @Test func test_pendingShowsSpinner() throws {
        #expect(try model("partial", pending: true).showsSpinner)
        #expect(try !model("partial", pending: false).showsSpinner)
        #expect(try !model("partial").showsSpinner)
    }

    @Test func test_backendLabelIsShownVerbatim() throws {
        #expect(try model("verified").label == "Backend label")
    }

    @Test func test_notAnObjectGivesNoBadge() {
        #expect(VerificationBadgeModel(.null) == nil)
        #expect(VerificationBadgeModel(.string("verified")) == nil)
    }

    @Test func test_checksAreReadLeniently() throws {
        let json: JSONValue = .object([
            "level": .string("partial"),
            "label": .string("Partly verified"),
            "summary": .string("2 of 3 found"),
            "checks": .array([
                .object([
                    "label": .string("Official site"), "status": .string("pass"), "url": .string("https://example.com/x"),
                ]),
                .object(["label": .string("Odd"), "status": .string("weird"), "url": .string("javascript:alert(1)")]),
                .object(["label": .string("Plain http"), "url": .string("http://example.com/y")]),
                .object(["label": .string("Failed"), "status": .string("fail"), "detail": .string("")]),
            ]),
        ])
        let model = try #require(VerificationBadgeModel(json))
        #expect(model.summary == "2 of 3 found")
        #expect(model.checks.count == 4)
        #expect(model.checks[0].status == .pass)
        #expect(model.checks[0].url?.host() == "example.com")
        #expect(model.checks[1].status == .info)
        #expect(model.checks[1].url == nil)
        #expect(model.checks[2].url == nil)
        #expect(model.checks[3].detail == nil)
    }
}
