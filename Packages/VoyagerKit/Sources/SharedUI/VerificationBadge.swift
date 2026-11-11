import DesignSystem
import L10n
import SwiftUI
import VoyagerModel

/// What the backend's `verification` object says, read leniently. The text is the backend's; nothing is invented
/// except the level's catalogue name when the backend sent no label.
public struct VerificationBadgeModel: Equatable, Sendable {
    public enum Level: String, Sendable, CaseIterable {
        case verified, partial, unverified, conflict
    }

    public enum CheckStatus: String, Sendable {
        case pass, fail, info
    }

    public struct Check: Equatable, Sendable, Identifiable {
        public let id: Int
        public let label: String
        public let status: CheckStatus
        public let detail: String?
        public let url: URL?
    }

    public let level: Level
    public let label: String
    public let summary: String?
    public let checks: [Check]
    public let pending: Bool

    /// `nil` when `verification` is not an object (the web renders nothing then).
    public init?(_ verification: JSONValue) {
        guard verification.object != nil else { return nil }
        // An unknown or missing level is styled as `unverified`.
        level = verification["level"].string.flatMap(Level.init(rawValue:)) ?? .unverified
        let text = verification["label"].string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        label = text.isEmpty ? Self.levelName(level) : text
        summary = Self.nonEmpty(verification["summary"].string)
        pending = verification["pending"].isTruthy
        checks = (verification["checks"].array ?? []).enumerated().map { index, item in
            Check(
                id: index,
                label: item["label"].string ?? "",
                status: item["status"].string.flatMap(CheckStatus.init(rawValue:)) ?? .info,
                detail: Self.nonEmpty(item["detail"].string),
                url: Self.safeSourceURL(item["url"].string)
            )
        }
    }

    /// Emerald, amber, gray, red.
    public var family: Family {
        switch level {
        case .verified: .emerald
        case .partial: .amber
        case .unverified: .gray
        case .conflict: .red
        }
    }

    /// Whether the chip shows a pending spinner.
    public var showsSpinner: Bool { pending }

    private static func levelName(_ level: Level) -> String {
        switch level {
        case .verified: L10n.text(K.misc.verification.level.verified)
        case .partial: L10n.text(K.misc.verification.level.partial)
        case .unverified: L10n.text(K.misc.verification.level.unverified)
        case .conflict: L10n.text(K.misc.verification.level.conflict)
        }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// Source links are display-only; http and https with a host.
    static func safeSourceURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http", url.host() != nil
        else { return nil }
        return url
    }
}

/// The section-header chip: coloured by `level`, showing the backend `label`. Tapping opens the details
/// (popover on iPad, sheet on iPhone).
public struct VerificationBadge: View {
    private let model: VerificationBadgeModel?
    @State private var presented = false

    public init(verification: JSONValue) {
        model = VerificationBadgeModel(verification)
    }

    public var body: some View {
        if let model {
            Button {
                presented = true
            } label: {
                HStack(spacing: Spacing.xs) {
                    if model.showsSpinner {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: Self.symbol(model.level)).accessibilityHidden(true)
                    }
                    Text(verbatim: model.label)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(VFont.body(.caption, weight: .semibold))
                .foregroundStyle(Palette.color(model.family, .s700))
                .padding(.horizontal, Spacing.sm)
                .frame(minHeight: 44)
                .background(Palette.color(model.family, .s100), in: Capsule())
                .overlay { Capsule().strokeBorder(Palette.color(model.family, .s200), lineWidth: 1) }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text(K.misc.verification.detailsAria, ["label": model.label]))
            .accessibilityIdentifier("verification.badge")
            .popover(isPresented: $presented) {
                VerificationDetails(model: model)
                    .presentationCompactAdaptation(.sheet)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private static func symbol(_ level: VerificationBadgeModel.Level) -> String {
        switch level {
        case .verified: "checkmark.seal.fill"
        case .partial: "questionmark.diamond"
        case .unverified: "sparkles"
        case .conflict: "exclamationmark.triangle.fill"
        }
    }
}

private struct VerificationDetails: View {
    let model: VerificationBadgeModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(verbatim: model.label)
                    .font(VFont.display(.headline))
                    .foregroundStyle(SemanticColor.text)
                if let summary = model.summary {
                    Text(verbatim: summary)
                        .font(VFont.body(.subheadline))
                        .foregroundStyle(SemanticColor.textMuted)
                }
                if model.pending {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                        Text(verbatim: L10n.text(K.misc.verification.checking))
                            .font(VFont.body(.subheadline))
                            .foregroundStyle(SemanticColor.textMuted)
                    }
                    .accessibilityElement(children: .combine)
                }
                ForEach(model.checks) { check in
                    CheckRow(check: check)
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 280, idealWidth: 320)
        .background(SemanticColor.surfaceRaised)
        .accessibilityLabel(L10n.text(K.misc.verification.dialogAria, ["label": model.label]))
    }
}

private struct CheckRow: View {
    let check: VerificationBadgeModel.Check

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: check.label)
                    .font(VFont.body(.subheadline, weight: .medium))
                    .foregroundStyle(SemanticColor.text)
                if let detail = check.detail {
                    Text(verbatim: detail)
                        .font(VFont.body(.footnote))
                        .foregroundStyle(SemanticColor.textMuted)
                }
                if let url = check.url {
                    Link(destination: url) {
                        Text(verbatim: L10n.text(K.misc.verification.source))
                            .font(VFont.body(.footnote, weight: .medium))
                    }
                    .tint(SemanticColor.primary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(statusName)
    }

    private var symbol: String {
        switch check.status {
        case .pass: "checkmark.circle.fill"
        case .fail: "xmark.circle.fill"
        case .info: "info.circle"
        }
    }

    private var tint: Color {
        switch check.status {
        case .pass: Palette.color(.emerald, .s600)
        case .fail: Palette.color(.red, .s600)
        case .info: SemanticColor.textMuted
        }
    }

    private var statusName: String {
        switch check.status {
        case .pass: L10n.text(K.misc.verification.check.pass)
        case .fail: L10n.text(K.misc.verification.check.fail)
        case .info: L10n.text(K.misc.verification.check.info)
        }
    }
}
