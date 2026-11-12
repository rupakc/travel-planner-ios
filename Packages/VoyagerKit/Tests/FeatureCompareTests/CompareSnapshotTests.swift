import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureCompare

@MainActor
final class CompareSnapshotTests: XCTestCase {
    private let configs: [SnapshotConfig] = [
        SnapshotConfig(name: "se-light", device: .iPhoneSe(.portrait), dark: false, canvas: CGSize(width: 320, height: 2600)),
        SnapshotConfig(name: "se-dark", device: .iPhoneSe(.portrait), dark: true, canvas: CGSize(width: 320, height: 2600)),
        SnapshotConfig(name: "ipad-light", device: .iPadPro11(.portrait), dark: false, canvas: CGSize(width: 834, height: 2200)),
    ]

    func test_threeColumns() async {
        await assertSnapshots(
            of: {
                let env = AppEnvironment.fake()
                let model = CompareModel(env: env, now: Date(timeIntervalSince1970: 1_800_000_000), track: { _ in })
                model.origin = "London"
                model.nationality = "British"
                model.destinations = ["Lisbon", "Rome", "Athens"]
                let request = TravelSearchRequest()
                model.show([
                    CompareColumn(
                        destination: "Lisbon, Portugal", request: request,
                        status: .done(
                            CompareSummary(
                                destination: "Lisbon", label: "Lisbon, Portugal",
                                flight: CompareFlight(priceUsd: 180, stops: 0, durationMinutes: 165, airline: "TAP"),
                                hotel: CompareHotel(typicalNightlyUsd: 110, cheapestGoodNightlyUsd: 78),
                                weather: CompareWeather(avgHighC: 24, avgLowC: 15, poorDays: 1, totalDays: 7, source: "open-meteo"),
                                visa: CompareVisa(visaType: "visa_free", maxStayDays: 90, feeUsd: 0, verified: true),
                                ease: CompareEase(total: 82, grade: "green", safety: 17, english: 15),
                                dailyCostUsd: 140,
                                estimate: CompareEstimate(totalUsd: 1450, budgetStatus: "under")))),
                    CompareColumn(
                        destination: "Rome", request: request,
                        status: .done(
                            CompareSummary(
                                destination: "Rome", label: "Rome, Italy",
                                flight: CompareFlight(priceUsd: 210, stops: 1, durationMinutes: 240, source: "estimate"),
                                hotel: CompareHotel(typicalNightlyUsd: 150),
                                weather: CompareWeather(avgHighC: 27, avgLowC: 17, poorDays: 0, totalDays: 7, source: "climate"),
                                visa: CompareVisa(visaType: "evisa", maxStayDays: 30, feeUsd: 25, verified: false),
                                ease: CompareEase(total: 64, grade: "amber", safety: 14, english: 12),
                                dailyCostUsd: 175,
                                estimate: CompareEstimate(totalUsd: 1800, partial: true, budgetStatus: "over"),
                                missing: ["activities"]))),
                    CompareColumn(destination: "Athens", request: request, status: .failed("Service unavailable — try again")),
                ])
                return CompareView(model: model)
            }, named: "three", configs: configs, layout: .screen)
    }
}
