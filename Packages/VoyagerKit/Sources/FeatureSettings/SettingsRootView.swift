import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// The You tab: account, appearance, language, privacy, notifications, features, rows to the other screens,
/// the Debug-only server, feedback and About.
public struct SettingsRootView: View {
    @State private var model: SettingsModel
    @State private var showsFeedback = false
    private let feedbackModel: FeedbackModel?

    @MainActor public init(env: AppEnvironment) {
        _model = State(initialValue: SettingsModel(env: env))
        feedbackModel = nil
    }

    @MainActor init(model: SettingsModel, feedbackModel: FeedbackModel? = nil) {
        _model = State(initialValue: model)
        self.feedbackModel = feedbackModel
    }

    public var body: some View {
        ScrollView {
            // VStack, not LazyVStack: lazy stacks hang hosted snapshot tests.
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                AppearanceSection(model: model)
                LanguagePicker(model: model)
                PrivacySection(model: model)
                NotificationsSection(model: model)
                FeaturesSection(model: model)
                shortcuts
                if model.showsServerSection { ServerSection(model: model) }
                feedback
                AboutSection(model: model)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(SemanticColor.surface)
        .navigationTitle(L10n.text(K.mobile.tabs.you))
        .sheet(isPresented: $showsFeedback) {
            if let feedbackModel {
                FeedbackSheet(model: feedbackModel) { showsFeedback = false }
            } else {
                FeedbackSheet(env: model.env) { showsFeedback = false }
            }
        }
        .accessibilityIdentifier("settings.root")
    }

    private var header: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 40)).foregroundStyle(SemanticColor.primary).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: model.username)
                            .font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                            .accessibilityIdentifier("settings.username")
                        if model.isAdmin {
                            VChip(title: L10n.text(K.common.nav.adminBadge), tid: "settings.adminBadge", selected: true) {}
                                .allowsHitTesting(false)
                        }
                    }
                    Spacer(minLength: 0)
                }
                VButton(
                    L10n.text(K.common.nav.signOut), tid: "settings.signOut", role: .secondary,
                    systemImage: "rectangle.portrait.and.arrow.right"
                ) { Task { await model.signOut() } }
                .disabled(model.signingOut)
            }
        }
    }

    private var shortcuts: some View {
        SettingsGroup(title: L10n.text(K.mobile.settings.account)) {
            SettingsLinkRow(title: L10n.text(K.common.nav.preferences), icon: "slider.horizontal.3", tid: "settings.preferences") {
                model.open(.preferences)
            }
            SettingsLinkRow(title: L10n.text(K.account.prefs.taste.title), icon: "heart.text.square", tid: "settings.taste") {
                model.open(.tasteProfile)
            }
            SettingsLinkRow(title: L10n.text(K.mobile.settings.retakeOnboarding), icon: "list.clipboard", tid: "settings.onboarding") {
                model.open(.onboarding(fromSettings: true))
            }
            if model.showsAdminRow {
                SettingsLinkRow(title: L10n.text(K.common.nav.admin), icon: "shield", tid: "settings.admin") {
                    model.open(.admin)
                }
            }
        }
    }

    private var feedback: some View {
        VButton(L10n.text(K.misc.feedback.trigger), tid: "settings.feedback", role: .tonal, systemImage: "bubble.left") {
            showsFeedback = true
        }
    }
}
