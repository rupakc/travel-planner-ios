import DesignSystem
import L10n
import SwiftUI
import VoyagerModel

/// The copy for a failure: the backend's text when it sent one (a rate limit shows it as-is), else the web copy.
/// `.unauthorized` is always the session-expired copy.
public enum ErrorCopy {
    public static func message(kind: ErrorPresentationKind, detail: String?) -> String {
        // A stale session always gets the catalogue copy, whatever the backend said.
        if kind == .unauthorized { return L10n.text(K.mobile.session.expired) }
        if let detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return detail }
        switch kind {
        case .unauthorized: return L10n.text(K.mobile.session.expired)
        case .rateLimited: return L10n.text(K.errors.rate_limited)
        case .network: return L10n.text(K.common.error.network)
        case .server, .other: return L10n.text(K.errors.generic)
        }
    }
}

public struct ErrorState: View {
    private let error: (any ErrorPresentable)?
    private let retry: (() -> Void)?

    public init(error: (any ErrorPresentable)?, retry: (() -> Void)? = nil) {
        self.error = error
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(SemanticColor.destructive)
                .accessibilityHidden(true)
            Text(verbatim: ErrorCopy.message(kind: error?.presentationKind ?? .other, detail: error?.userFacingDetail))
                .font(VFont.body(.subheadline))
                .foregroundStyle(SemanticColor.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let retry {
                VButton(L10n.text(K.alerts.ui.retry), tid: "error.retry", role: .secondary, action: retry)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}
