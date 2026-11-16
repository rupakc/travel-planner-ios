import Foundation
import L10n
import Observation
import Telemetry
import VoyagerEnv
import VoyagerModel

/// The report sheet for a profile (`POST /social/reports`, `target: profile`). Any of the six reasons, an optional note of
/// at most 200 characters; sending twice is harmless (the server counts a reporter once).
@MainActor @Observable
final class ProfileReportModel {
    enum Phase: Equatable {
        case editing
        case sending
        case sent
        case failed(String)
    }

    let handle: String
    var reason: ReportReason = .spam
    private(set) var note = ""
    private(set) var phase: Phase = .editing

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let emit: @MainActor (TelemetryEvent) -> Void

    init(env: AppEnvironment, handle: String, track: (@MainActor (TelemetryEvent) -> Void)? = nil) {
        self.env = env
        self.handle = handle
        let telemetry = env.telemetry
        self.emit = track ?? { telemetry.track($0) }
    }

    func setNote(_ text: String) {
        note = String(text.prefix(ReportRequest.maxNote))
    }

    static func title(for reason: ReportReason) -> String {
        switch reason {
        case .spam: L10n.text(K.social.report.reason.spam)
        case .abuse: L10n.text(K.social.report.reason.abuse)
        case .sexual: L10n.text(K.social.report.reason.sexual)
        case .violence: L10n.text(K.social.report.reason.violence)
        case .misinformation: L10n.text(K.social.report.reason.misinformation)
        case .other: L10n.text(K.social.report.reason.other)
        }
    }

    func send() async {
        guard phase != .sending, phase != .sent else { return }
        phase = .sending
        let request = ReportRequest(target: .profile, id: handle, reason: reason, note: note)
        do {
            try await env.social.call { try await $0.report(request) }
            phase = .sent
            emit(.socialReport(target: "profile", reason: reason.rawValue))
        } catch is CancellationError {
            phase = .editing
        } catch {
            phase = .failed(SocialMessage.text(for: error))
        }
    }
}
