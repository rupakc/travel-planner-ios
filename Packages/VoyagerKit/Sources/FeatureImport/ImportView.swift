import DesignSystem
import L10n
import SharedUI
import SwiftUI
import UIKit
import VoyagerEnv
import VoyagerModel

/// "From a link": paste a link or text, or pick up to 4 screenshots; review the places; plan the trip.
/// Entry points: the Explore "Link" mode, `voyager://import?url=` and the chat `import_link` event.
public struct ImportView: View {
    @State private var model: ImportModel
    let initialURL: URL?

    @MainActor public init(env: AppEnvironment, initialURL: URL?) {
        _model = State(initialValue: ImportModel(env: env))
        self.initialURL = initialURL
    }

    @MainActor init(model: ImportModel) {
        _model = State(initialValue: model)
        initialURL = nil
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                switch model.phase {
                case .input: form
                case .loading: loading
                case .review: ImportReview(model: model)
                case .failed(let error): failure(error)
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .task { await model.prefill(url: initialURL) }
        .accessibilityIdentifier("import.root")
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(verbatim: L10n.text(K.search.import.heading))
                .font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
            Text(verbatim: L10n.text(K.search.import.subheading))
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            VCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(verbatim: L10n.text(K.search.import.pasteLabel))
                        .font(VFont.body(.footnote, weight: .medium)).foregroundStyle(SemanticColor.textMuted)
                    TextField(L10n.text(K.search.import.placeholder), text: $model.text, axis: .vertical)
                        .lineLimit(3...8)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.default)
                        .disabled(!model.shots.isEmpty)
                        .accessibilityIdentifier("import.input")
                    detectedHint
                    shotsRow
                    if let problem = model.fileProblem {
                        Text(verbatim: problem).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.destructive)
                            .accessibilityIdentifier("import.fileProblem")
                    }
                    ScreenshotPicker(remaining: ScreenshotEncoder.maxImages - model.shots.count) { datas in
                        Task { await model.addScreenshots(datas) }
                    }
                    VButton(
                        model.shots.isEmpty
                            ? L10n.text(K.search.import.find)
                            : L10n.text(K.search.import.findInShots, count: model.shots.count),
                        tid: "import.find", systemImage: "sparkles"
                    ) { Task { await model.extract() } }
                    .disabled(!model.canFind)
                }
            }
            examples
        }
    }

    @ViewBuilder private var detectedHint: some View {
        switch model.detected {
        case .url:
            Text(verbatim: L10n.text(K.search.import.detectedUrl)).font(VFont.body(.caption))
                .foregroundStyle(SemanticColor.textMuted)
        case .text:
            Text(verbatim: L10n.text(K.search.import.detectedText)).font(VFont.body(.caption))
                .foregroundStyle(SemanticColor.textMuted)
        case .empty:
            EmptyView()
        }
    }

    @ViewBuilder private var shotsRow: some View {
        if !model.shots.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: L10n.text(K.search.import.shotsNote, count: model.shots.count))
                    .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                HStack(spacing: Spacing.sm) {
                    ForEach(model.shots) { shot in
                        ZStack(alignment: .topTrailing) {
                            thumbnail(shot).frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.input))
                            Button { model.removeShot(shot.id) } label: {
                                Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .accessibilityLabel(L10n.text(K.search.import.removeShot, ["name": L10n.text(K.search.import.screenshot)]))
                        }
                    }
                    let counter = ["n": "\(model.shots.count)", "max": "\(ScreenshotEncoder.maxImages)"]
                    Text(verbatim: L10n.text(K.search.import.counter, counter))
                        .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                }
            }
        }
    }

    @ViewBuilder private func thumbnail(_ shot: ImportShot) -> some View {
        if let data = Data(base64Encoded: shot.image.dataBase64), let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Rectangle().fill(SemanticColor.surfaceRaised)
        }
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: L10n.text(K.search.import.examples)).font(VFont.body(.footnote))
                .foregroundStyle(SemanticColor.textMuted)
            HStack {
                VChip(title: L10n.text(K.search.import.example.lisbon.label), tid: "import.example.lisbon", selected: false) {
                    model.useText(L10n.text(K.search.import.example.lisbon.text))
                }
                VChip(title: L10n.text(K.search.import.example.tokyo.label), tid: "import.example.tokyo", selected: false) {
                    model.useText(L10n.text(K.search.import.example.tokyo.text))
                }
                VChip(title: L10n.text(K.search.import.example.rome.label), tid: "import.example.rome", selected: false) {
                    model.useText(L10n.text(K.search.import.example.rome.text))
                }
            }
        }
    }

    private var loading: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(verbatim: L10n.text(K.search.import.steps.find)).font(VFont.body(.subheadline, weight: .medium))
                .foregroundStyle(SemanticColor.text)
            Skeleton(lines: 5)
        }
        .accessibilityIdentifier("import.loading")
    }

    private func failure(_ error: ImportErrorView) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: error.message).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.destructive)
                    .accessibilityIdentifier("import.error")
                ForEach(error.actions, id: \.rawValue) { action in
                    VButton(Self.title(action), tid: "import.action.\(action.rawValue)", role: .secondary) {
                        model.recover(action)
                        if action == .retry { Task { await model.extract() } }
                    }
                }
                VButton(L10n.text(K.search.import.cancel), tid: "import.cancel", role: .secondary) { model.startOver() }
            }
        }
    }

    private static func title(_ action: ImportErrorView.Action) -> String {
        switch action {
        case .text: L10n.text(K.search.import.actions.text)
        case .images: L10n.text(K.search.import.actions.images)
        case .retry: L10n.text(K.search.import.actions.retry)
        }
    }
}
