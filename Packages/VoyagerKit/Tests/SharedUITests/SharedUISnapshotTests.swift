import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerModel
import XCTest

@testable import SharedUI

private struct FakeError: ErrorPresentable {
    let presentationKind: ErrorPresentationKind
    let userFacingDetail: String?
}

@MainActor
final class SharedUISnapshotTests: XCTestCase {
    func test_vButton() async {
        await assertSnapshots(
            of: {
                VStack(spacing: 12) {
                    VButton("Search flights", tid: "snap.primary", systemImage: "airplane") {}
                    VButton("Save plan", tid: "snap.secondary", role: .secondary) {}
                    VButton("Clear", tid: "snap.tonal", role: .tonal) {}
                    VButton("Delete trip", tid: "snap.destructive", role: .destructive) {}
                }
            }, named: "buttons", configs: SnapshotConfig.standard)
    }

    func test_errorState() async {
        await assertSnapshots(
            of: {
                ErrorState(
                    error: FakeError(presentationKind: .rateLimited, userFacingDetail: nil),
                    retry: {})
            }, named: "rate-limited", configs: SnapshotConfig.standard)
    }

    func test_verificationBadge() async {
        func badge(_ level: String, _ label: String, pending: Bool = false) -> JSONValue {
            .object(["level": .string(level), "label": .string(label), "pending": .bool(pending)])
        }
        await assertSnapshots(
            of: {
                VStack(alignment: .leading, spacing: 8) {
                    VerificationBadge(verification: badge("verified", "Verified"))
                    VerificationBadge(verification: badge("partial", "Partly verified", pending: true))
                    VerificationBadge(verification: badge("unverified", "AI-generated"))
                    VerificationBadge(verification: badge("conflict", "Check details"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }, named: "levels", configs: SnapshotConfig.standard)
    }

    func test_priceTextEstimate() async {
        await assertSnapshots(
            of: {
                VStack(alignment: .leading, spacing: 12) {
                    PriceText(amount: 1249.5, currency: "USD", estimate: true)
                    PriceText(amount: 89, currency: "EUR", estimate: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }, named: "estimate", configs: SnapshotConfig.standard)
    }
}
