import DesignSystem
import L10n
import SectionsUI
import SharedUI
import SwiftUI
import VoyagerEnv

#if canImport(UIKit)
import SafariServices
#endif

/// The chat screen. The model is owned here through `@State`, so rotating and Split View resizes keep the
/// stream. iPad (regular width): the threads list beside the conversation; iPhone: a button opens the list.
public struct ChatRootView: View {
    @State private var model: ChatModel
    @State private var showThreads = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    private let env: AppEnvironment
    private let lazyStack: Bool

    @MainActor public init(env: AppEnvironment) {
        self.env = env
        lazyStack = true
        _model = State(initialValue: ChatModel(env: env))
    }

    /// Tests and snapshots: a prepared model (and a plain stack, since lazy stacks hang hosted snapshot tests).
    @MainActor init(env: AppEnvironment, model: ChatModel, lazyStack: Bool = false) {
        self.env = env
        self.lazyStack = lazyStack
        _model = State(initialValue: model)
    }

    public var body: some View {
        let regular = AdaptiveLayout.isRegular(sizeClass)
        Group {
            if regular {
                HStack(spacing: 0) {
                    threads.frame(width: 300)
                    Divider()
                    conversation(layout: .regular)
                }
            } else {
                conversation(layout: .compact)
            }
        }
        .background(SemanticColor.surface)
        // An opaque bar: the conversation scrolls under it, and its text never shows through the bar's buttons.
        .toolbarBackground(SemanticColor.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !regular {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showThreads = true } label: {
                        Label { Text(verbatim: L10n.text(K.chat.page.title)) } icon: { Image(systemName: "list.bullet") }
                    }
                    .accessibilityIdentifier("chat.threads")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.clear() } label: {
                    Label { Text(verbatim: L10n.text(K.chat.page.clear)) } icon: { Image(systemName: "trash") }
                }
                .disabled(model.messages.isEmpty)
                .accessibilityIdentifier("chat.clear")
            }
        }
        .sheet(isPresented: $showThreads) {
            threads.presentationDetents([.medium, .large])
        }
        .toast($model.toast)
        #if canImport(UIKit)
        .fullScreenCover(item: safariBinding) { item in
            ChatSafariCover(url: item.url).ignoresSafeArea()
        }
        #endif
        .telemetryRoute("/chat")
        .task { model.resumeLatestIfFresh() }
        .accessibilityIdentifier("chat.root")
    }

    private var threads: some View {
        ThreadsList(
            threads: env.chatThreads.threads, selected: model.threadID,
            onNew: { model.newThread(); showThreads = false },
            onOpen: { model.open($0); showThreads = false },
            onDelete: { model.deleteThread($0) })
    }

    private func conversation(layout: LayoutClass) -> some View {
        VStack(spacing: 0) {
            if model.messages.isEmpty {
                intro
            } else {
                MessageList(
                    messages: model.messages, isStreaming: model.isStreaming, ctx: model.makeContext(layout: layout),
                    lazy: lazyStack, onSuggestion: { model.send($0) }, onImport: { model.openImport($0) },
                    onRetry: { model.retry() })
            }
            Divider().overlay(SemanticColor.border)
            Composer(text: $model.input, isStreaming: model.isStreaming, onSend: { model.send(model.input) }, onStop: { model.stop() })
        }
        .frame(maxWidth: .infinity)
    }

    private var intro: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // No large icon: the title, intro and four chips must fit an iPhone SE without scrolling.
                VStack(spacing: Spacing.sm) {
                    Text(verbatim: L10n.text(K.chat.page.title))
                        .font(VFont.display(.title3)).foregroundStyle(SemanticColor.text).multilineTextAlignment(.center)
                    Text(verbatim: L10n.text(K.chat.page.intro))
                        .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted).multilineTextAlignment(.center)
                }
                SuggestionChips(
                    chips: [K.chat.suggestion._1, K.chat.suggestion._2, K.chat.suggestion._3, K.chat.suggestion._4].map { L10n.text($0) },
                    onTap: { model.send($0) })
                Text(verbatim: L10n.text(K.chat.page.disclaimer))
                    .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted).multilineTextAlignment(.center)
            }
            .padding(Spacing.lg)
        }
    }

    #if canImport(UIKit)
    private var safariBinding: Binding<ChatSafariItem?> {
        Binding(
            get: { model.safariURL.map(ChatSafariItem.init) },
            set: { if $0 == nil { model.safariURL = nil } })
    }
    #endif
}

#if canImport(UIKit)
private struct ChatSafariItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ChatSafariCover: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(SemanticColor.primary)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
