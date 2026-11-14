import SharedUI
import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerModel
import XCTest

@testable import FeatureAlerts

@MainActor
final class PriceStorySnapshotTests: XCTestCase {
    private let phone: [SnapshotConfig] = [
        SnapshotConfig(name: "se-light", device: .iPhoneSe(.portrait), dark: false, canvas: CGSize(width: 320, height: 420)),
        SnapshotConfig(name: "se-dark", device: .iPhoneSe(.portrait), dark: true, canvas: CGSize(width: 320, height: 420)),
    ]

    private let tall = SnapshotConfig(
        name: "se-light", device: .iPhoneSe(.portrait), dark: false, canvas: CGSize(width: 320, height: 560))

    /// The story as it sits in a watch card: inside a `VCard`, on the screen surface.
    private func card(
        _ story: PriceStory, kind: WatchKind = .flight, tip: AdviceTipState = .idle, selected: PricePoint? = nil
    ) -> some View {
        let model = storyModel(kind, id: story.watchId)
        model.show(story, tip: tip, selected: selected)
        return VCard { PriceStoryView(model: model) }
    }

    func test_goodLight() async {
        await assertSnapshots(
            of: { self.card(goodFlightStory, selected: goodFlightStory.points[2]) }, named: "StoryGood",
            configs: [phone[0]], layout: .component)
    }

    func test_goodWithTip() async {
        await assertSnapshots(
            of: { self.card(goodFlightStory, tip: .tip(AdviceTip(tip: "Fares on this route usually dip about three weeks out, so waiting a little may pay off."))) },
            named: "StoryTip", configs: [tall], layout: .component)
    }

    func test_highDark() async {
        await assertSnapshots(
            of: { self.card(highHotelStory, kind: .hotel) }, named: "StoryHigh", configs: [phone[1]], layout: .component)
    }

    func test_pending() async {
        await assertSnapshots(
            of: { self.card(pendingStory, kind: .hotel) }, named: "StoryPending", configs: phone, layout: .component)
    }

    func test_tipError() async {
        await assertSnapshots(
            of: { self.card(goodFlightStory, tip: .failed("The AI limit is reached for this month.")) },
            named: "StoryTipError", configs: [tall], layout: .component)
    }

    func test_checksPausedGerman() async {
        await assertSnapshots(
            of: { self.card(pausedStory) }, named: "StoryChecksPaused",
            configs: [
                SnapshotConfig(
                    name: "se-de", device: .iPhoneSe(.portrait), dark: false, language: .de,
                    canvas: CGSize(width: 320, height: 440))
            ], layout: .component)
    }

    func test_accessibilityXXXL() async {
        await assertSnapshots(
            of: { self.card(goodFlightStory) }, named: "StoryAX5",
            configs: [
                SnapshotConfig(
                    name: "se-ax5", device: .iPhoneSe(.portrait), dark: false, size: .accessibilityExtraExtraExtraLarge,
                    canvas: CGSize(width: 320, height: 780))
            ], layout: .component)
    }

    func test_regularWidth() async {
        await assertSnapshots(
            of: { self.card(goodFlightStory) }, named: "StoryRegular",
            configs: [
                SnapshotConfig(name: "ipad-light", device: .iPadPro11(.portrait), dark: false, canvas: CGSize(width: 834, height: 460))
            ], layout: .component)
    }
}
