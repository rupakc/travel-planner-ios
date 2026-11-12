import DesignSystem
import SnapshotTesting
import SwiftUI
import VoyagerModel
import XCTest

@testable import SectionsUI

@MainActor
final class SectionCardSnapshotTests: XCTestCase {
    private struct Host<C: View>: View {
        @State var open = true
        let id: SectionID
        let status: SectionStatus
        var verification: JSONValue?
        @ViewBuilder let content: () -> C

        var body: some View {
            SectionCard(id: id, status: status, verification: verification, expanded: $open, content: content)
        }
    }

    private static var sample: JSONValue {
        .object(["results": .array([.object(["name": .string("Skyline Hotel"), "price_usd": .number(180), "rating": .number(4.5)])])])
    }

    override func setUp() async throws {
        await FontRegistry.ready()
    }

    func test_loading() {
        assertSnapshots(of: { Host(id: .flights, status: .loading) { EmptyView() } }, named: "loading", configs: lean)
    }

    func test_enhancing() {
        assertSnapshots(
            of: { Host(id: .visa, status: .enhancing) { GenericSectionView(data: Self.sample, ctx: .inert) } },
            named: "enhancing", configs: lean)
    }

    func test_doneVerified() {
        let verified: JSONValue = .object(["level": .string("verified"), "label": .string("Verified")])
        assertSnapshots(
            of: { Host(id: .hotels, status: .done, verification: verified) { GenericSectionView(data: Self.sample, ctx: .inert) } },
            named: "done-verified")
    }

    func test_error() {
        assertSnapshots(of: { Host(id: .visa, status: .error("")) { EmptyView() } }, named: "error", configs: lean)
    }

    private var lean: [SnapshotConfig] { [.phoneLight, .padDark] }
}
