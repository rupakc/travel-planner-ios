import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerEnv
import VoyagerModel
#if canImport(UIKit)
import UIKit
#endif

/// The share sheet (`router.open(.shareSheet(target))`, plan ruling R5): choose what the link reveals, create it, then
/// "Share link" (the system sheet, with the card as the preview) or "Share image" (the story card), or copy it.
public struct ShareSheetView: View {
    @State private var model: ShareSheetModel
    @Environment(\.dismiss) private var dismiss

    @MainActor public init(env: AppEnvironment, target: ShareTarget) {
        _model = State(initialValue: ShareSheetModel(env: env, target: target))
    }

    @MainActor init(model: ShareSheetModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                // VStack, not LazyVStack: lazy stacks hang hosted snapshot tests.
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if model.isUnavailable {
                        Text(verbatim: L10n.text(K.share.errors.unavailable))
                            .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                            .accessibilityIdentifier("share.unavailable")
                    } else {
                        form
                    }
                }
                .frame(maxWidth: AdaptiveLayout.readableMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.lg)
            }
            .background(SemanticColor.surface)
            .navigationTitle(model.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text(K.share.close)) {
                        model.cancel()
                        dismiss()
                    }
                    .accessibilityIdentifier("share.close")
                }
            }
        }
        .telemetryRoute("/share-sheet")
        .onAppear { model.opened() }
        .onChange(of: model.outcome) { _, _ in
            if let status = model.status { LiveRegion.announce(status) }
        }
        .onDisappear { model.cancel() }
        .accessibilityIdentifier("share.sheet")
    }

    // MARK: Form

    @ViewBuilder private var form: some View {
        Text(verbatim: L10n.text(K.share.intro))
            .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
            .fixedSize(horizontal: false, vertical: true)
        if model.showsOptions {
            Text(verbatim: L10n.text(K.share.reveals))
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            optionsCard
        }
        createButton
        if model.showsOptions {
            Text(verbatim: L10n.text(K.share.sameLinkNote))
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("share.same-link-note")
        }
        if case .failed(let failure) = model.phase {
            Text(verbatim: failure.message)
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("share.error")
        }
        if model.hasLink { result }
    }

    private var optionsCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(verbatim: L10n.text(K.share.dates))
                    .font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
                    .accessibilityAddTraits(.isHeader)
                ForEach(ShareDates.allCases, id: \.self) { choice in
                    dateRow(choice)
                }
                Text(verbatim: L10n.text(K.share.datesNote))
                    .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Text(verbatim: L10n.text(K.share.optionsLegend))
                    .font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
                    .accessibilityAddTraits(.isHeader)
                toggle(L10n.text(K.share.showOrigin), tid: "share.show-origin", isOn: $model.options.showOrigin)
                toggle(L10n.text(K.share.showName), tid: "share.show-name", isOn: $model.options.showName)
            }
        }
    }

    private func dateRow(_ choice: ShareDates) -> some View {
        let selected = model.options.dates == choice
        return Button {
            model.options.dates = choice
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? SemanticColor.primary : SemanticColor.textMuted)
                    .accessibilityHidden(true)
                Text(verbatim: L10n.text(dateKey(choice)))
                    .font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("share.dates-\(choice.rawValue)")
    }

    private func dateKey(_ choice: ShareDates) -> LKey {
        switch choice {
        case .hidden: K.share.datesHidden
        case .month: K.share.datesMonth
        case .exact: K.share.datesExact
        }
    }

    private func toggle(_ title: String, tid: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(verbatim: title).font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(SemanticColor.primary)
        .frame(minHeight: 44)
        .telemetryToggle(tid: tid, value: isOn.wrappedValue)
        .accessibilityIdentifier(tid)
    }

    private var createButton: some View {
        HStack(spacing: Spacing.md) {
            // Nothing to update yet: the same button in the quiet style, still fully readable (never faded).
            VButton(model.primaryTitle, tid: "share.create", role: model.canCreate ? .primary : .secondary) {
                Task { await model.create() }
            }
            .disabled(!model.canCreate)
            if model.isWorking { ProgressView().accessibilityHidden(true) }
        }
    }

    // MARK: Result

    @ViewBuilder private var result: some View {
        if model.offersCard { cardPreview }
        if let url = model.linkURL {
            Text(verbatim: url.absoluteString)
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                .textSelection(.enabled)
                .lineLimit(3)
                .accessibilityLabel(Text(verbatim: L10n.text(K.share.urlLabel)))
                .accessibilityValue(Text(verbatim: url.absoluteString))
                .accessibilityIdentifier("share.url")
            actions(url)
        }
        if let status = model.status {
            Text(verbatim: status)
                .font(VFont.body(.footnote))
                .foregroundStyle(model.copyFailed ? SemanticColor.destructive : SemanticColor.textMuted)
                .accessibilityIdentifier("share.status")
        }
        if model.offersCard, model.storyCard == .unavailable, model.linkCard == .unavailable {
            Text(verbatim: L10n.text(K.share.errors.download))
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                .accessibilityIdentifier("share.card-unavailable")
        }
    }

    @ViewBuilder private var cardPreview: some View {
        switch model.linkCard {
        case .ready(let file):
            if let image = ShareCardImage.image(at: file) {
                image.resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Radius.itemCard))
                    .overlay { RoundedRectangle(cornerRadius: Radius.itemCard).strokeBorder(SemanticColor.border, lineWidth: 1) }
                    .accessibilityLabel(Text(verbatim: L10n.text(K.share.preview)))
                    .accessibilityIdentifier("share.card")
            }
        case .loading, .idle:
            RoundedRectangle(cornerRadius: Radius.itemCard)
                .fill(Palette.color(.gray, .s200))
                .aspectRatio(1200.0 / 630.0, contentMode: .fit)
                .overlay { ProgressView() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: L10n.text(K.share.working)))
                .accessibilityIdentifier("share.card-loading")
        case .unavailable:
            EmptyView()
        }
    }

    private func actions(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ShareLink(
                item: url, message: model.shareText.map { Text(verbatim: $0) },
                preview: preview(title: model.shareText ?? model.title)
            ) {
                Label {
                    Text(verbatim: L10n.text(K.share.entry.link))
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .simultaneousGesture(TapGesture().onEnded { model.didShareNatively(tid: "share.native") })
            .accessibilityIdentifier("share.native")
            if case .ready(let file) = model.storyCard {
                ShareLink(item: ShareImage(fileURL: file), preview: preview(title: model.shareText ?? model.title)) {
                    Label {
                        Text(verbatim: L10n.text(K.mobile.share.image))
                    } icon: {
                        Image(systemName: "photo")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .simultaneousGesture(TapGesture().onEnded { model.didShareNatively(tid: "share.image") })
                .accessibilityIdentifier("share.image")
            }
            VButton(L10n.text(K.share.actions.copy), tid: "share.copy", role: .secondary, systemImage: "doc.on.doc") {
                model.copyLink()
            }
        }
    }

    /// The system share sheet's preview: the card when it is downloaded, else a link glyph.
    private func preview(title: String) -> SharePreview<Image, Never> {
        if case .ready(let file) = model.linkCard, let image = ShareCardImage.image(at: file) {
            return SharePreview(title, image: image)
        }
        return SharePreview(title, image: Image(systemName: "link"))
    }
}

#if canImport(UIKit)
/// Card PNGs decoded once per file (a hosted view re-renders its body often).
@MainActor
enum ShareCardImage {
    private static let cache = NSCache<NSURL, UIImage>()

    static func image(at file: URL) -> Image? {
        if let cached = cache.object(forKey: file as NSURL) { return Image(uiImage: cached) }
        guard let decoded = UIImage(contentsOfFile: file.path) else { return nil }
        cache.setObject(decoded, forKey: file as NSURL)
        return Image(uiImage: decoded)
    }
}
#endif
