import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerModel

/// "Search the web now" for one watch: the model's summary, the prices it found (each linked to its source
/// through `BookingLink`) and the sources. Shown from memory only: nothing here is stored.
struct LiveCheckSheet: View {
    let state: LiveCheckState
    let onDismiss: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.telemetryRoute) private var route

    var body: some View {
        NavigationStack {
            ScrollView {
                // VStack, not LazyVStack: lazy stacks hang hosted snapshot tests.
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text(verbatim: state.row.title)
                        .font(VFont.display(.headline))
                        .foregroundStyle(SemanticColor.text)
                    content
                }
                .frame(maxWidth: AdaptiveLayout.readableMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.lg)
            }
            .navigationTitle(L10n.text(K.alerts.live.heading))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text(K.alerts.dialog.close), action: onDismiss).accessibilityIdentifier("alerts.live-close")
                }
            }
        }
        .accessibilityIdentifier("alerts.live-sheet")
    }

    @ViewBuilder private var content: some View {
        switch state.phase {
        case .searching:
            HStack(spacing: Spacing.md) {
                ProgressView()
                Text(verbatim: L10n.text(K.alerts.live.searchingFor, ["title": state.row.title]))
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            }
        case .failed(let message):
            Text(verbatim: message).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.destructive)
        case .result(let result):
            resultBody(result)
        }
    }

    @ViewBuilder private func resultBody(_ result: LiveCheckResult) -> some View {
        if let summary = result.summary, !summary.isEmpty {
            Text(verbatim: summary).font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !result.quotes.isEmpty {
            section(L10n.text(K.alerts.live.pricesFound)) {
                ForEach(Array(result.quotes.enumerated()), id: \.offset) { _, quote in
                    quoteRow(quote, sources: result.sources)
                }
            }
        }
        if !result.searchedFor.isEmpty {
            section(L10n.text(K.alerts.live.searchedFor)) {
                ForEach(Array(result.searchedFor.enumerated()), id: \.offset) { _, query in
                    Text(verbatim: query).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                }
            }
        }
        if !result.sources.isEmpty {
            section(L10n.text(K.alerts.live.sources)) {
                ForEach(Array(result.sources.enumerated()), id: \.offset) { index, source in
                    sourceRow(source, tid: "alerts.live-source-\(index)")
                }
            }
        }
        Text(verbatim: result.disclaimer ?? L10n.text(K.alerts.live.disclaimer))
            .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: title).font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
            content()
        }
    }

    private func quoteRow(_ quote: LiveQuote, sources: [LiveSource]) -> some View {
        let source = quote.sourceIndex.flatMap { sources.indices.contains($0) ? sources[$0] : nil }
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(verbatim: quote.label ?? source?.title ?? "")
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                Spacer(minLength: Spacing.sm)
                if let amount = quote.amount {
                    PriceText(amount: amount, currency: quote.currency ?? "USD", estimate: false)
                }
            }
            if let url = source?.uri.flatMap(URL.init(string:)) {
                BookingLink(url: url, section: "live_check", tid: "alerts.live-quote-book")
            }
        }
    }

    @ViewBuilder private func sourceRow(_ source: LiveSource, tid: String) -> some View {
        if let url = source.uri.flatMap(URL.init(string:)), BookingLink.isAllowed(url), let domain = BookingLink.domain(of: url) {
            Button {
                Telemetry.shared.track(.uiTap(tid: tid, route: route))
                Telemetry.shared.track(.linkOut(section: "live_check", domain: domain))
                openURL(url)
            } label: {
                Text(verbatim: source.title ?? domain)
                    .font(VFont.body(.footnote))
                    .foregroundStyle(SemanticColor.primary)
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier(tid)
        }
    }
}
