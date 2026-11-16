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

    func test_loading() {
        assertSnapshots(of: { Host(id: .flights, status: .loading) { EmptyView() } }, named: "loading", configs: fit(se: 195, pad: 200))
    }

    func test_enhancing() {
        assertSnapshots(
            of: { Host(id: .visa, status: .enhancing) { GenericSectionView(data: Self.sample, ctx: .inert) } },
            named: "enhancing", configs: fit(se: 240, pad: 242))
    }

    func test_doneVerified() {
        let verified: JSONValue = .object(["level": .string("verified"), "label": .string("Verified")])
        assertSnapshots(
            of: { Host(id: .hotels, status: .done, verification: verified) { GenericSectionView(data: Self.sample, ctx: .inert) } },
            named: "done-verified")
    }

    func test_error() {
        assertSnapshots(of: { Host(id: .visa, status: .error("")) { EmptyView() } }, named: "error", configs: fit(se: 175, pad: 160))
    }

    /// Phone and pad, light and dark, on canvases cut to the content (no blank tail): `se` and `pad` are heights in points.
    private func fit(se: CGFloat, pad: CGFloat) -> [SnapshotConfig] {
        func sized(_ config: SnapshotConfig, _ height: CGFloat, _ width: CGFloat) -> SnapshotConfig {
            var copy = config
            copy.canvas = CGSize(width: width, height: height)
            return copy
        }
        return [
            sized(.phoneLight, se, 320), sized(.phoneDark, se, 320), sized(.padLight, pad, 834), sized(.padDark, pad, 834),
        ]
    }
}
