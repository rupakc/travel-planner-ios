import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv

/// How the onboarding ended.
public enum OnboardingOutcome: Sendable, Equatable {
    case completed, skipped
}

/// The shared 5-step onboarding (first run and "Edit my travel style" in Settings).
public struct OnboardingView: View {
    @State private var model: OnboardingModel
    private let fromSettings: Bool

    @MainActor public init(env: AppEnvironment, fromSettings: Bool, onFinish: @escaping @MainActor (OnboardingOutcome) -> Void) {
        self.fromSettings = fromSettings
        _model = State(initialValue: OnboardingModel(env: env, fromSettings: fromSettings, onFinish: onFinish))
    }

    /// For snapshots and previews: a prepared model.
    @MainActor init(model: OnboardingModel) {
        fromSettings = model.fromSettings
        _model = State(initialValue: model)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                stepContent
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.lg)
                    .readableWidth()
            }
            footer
                .padding(Spacing.lg)
                .readableWidth()
        }
        .background(SemanticColor.surface)
        .telemetryRoute("/onboarding")
        .task {
            model.start()
            if fromSettings { await model.loadExisting() }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            if model.canGoBack {
                Button { model.back() } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel(L10n.text(K.onboarding.nav.back))
                .accessibilityIdentifier("onboarding.back")
            }
            Text(verbatim: L10n.text(K.onboarding.nav.stepOf, ["step": "\(model.stepNumber)"], count: model.stepCount))
                .font(VFont.body(.footnote, weight: .medium))
                .foregroundStyle(SemanticColor.textMuted)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.sm)
            if fromSettings {
                Button { model.close() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .accessibilityLabel(L10n.text(K.onboarding.ui.close))
                .accessibilityIdentifier("onboarding.close")
            }
        }
        .foregroundStyle(SemanticColor.text)
        .padding(.horizontal, Spacing.sm)
        .frame(minHeight: 44)
        .readableWidth()
    }

    @ViewBuilder private var stepContent: some View {
        switch model.step {
        case .welcome: WelcomeStep()
        case .howYouTravel: HowYouTravelStep(model: model)
        case .homeAndPassport: HomeAndPassportStep(model: model)
        case .notifications: NotificationsStep()
        case .firstTrip: FirstTripStep()
        }
    }

    // MARK: - Footer

    @ViewBuilder private var footer: some View {
        if model.syncState != .idle {
            syncFooter
        } else {
            VStack(spacing: Spacing.sm) {
                switch model.step {
                case .notifications:
                    VButton(L10n.text(K.mobile.permissions.allow), tid: "onboarding.allow") {
                        Task { await model.allowNotifications() }
                    }
                    VButton(L10n.text(K.mobile.permissions.notNow), tid: "onboarding.notNow", role: .secondary) {
                        model.declineNotifications()
                    }
                case .firstTrip:
                    if fromSettings {
                        VButton(L10n.text(K.onboarding.ui.saveChanges), tid: "onboarding.save") { model.finish() }
                    } else {
                        VButton(L10n.text(K.onboarding.ui.planTrip), tid: "onboarding.plan") { model.finishAndPlan() }
                        VButton(L10n.text(K.onboarding.ui.exploreFirst), tid: "onboarding.explore", role: .secondary) {
                            model.finish()
                        }
                    }
                default:
                    VButton(primaryTitle, tid: "onboarding.next") { model.next() }
                    VButton(L10n.text(K.onboarding.nav.skip), tid: "onboarding.skip", role: .secondary) { model.skip() }
                }
            }
        }
    }

    private var primaryTitle: String {
        if let question = model.currentQuestion, question.id == TravellerQuizIDs.last {
            return L10n.text(K.onboarding.nav.seeType)
        }
        return L10n.text(K.onboarding.nav.next)
    }

    @ViewBuilder private var syncFooter: some View {
        VStack(spacing: Spacing.sm) {
            if model.syncState == .saving {
                ProgressView(L10n.text(K.onboarding.ui.saving))
                    .font(VFont.body(.subheadline))
            } else {
                Text(verbatim: L10n.text(K.onboarding.ui.saveFailed))
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.destructive)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VButton(L10n.text(K.alerts.ui.retry), tid: "onboarding.retry") { model.retrySync() }
                VButton(L10n.text(K.onboarding.ui.continueOffline), tid: "onboarding.continueOffline", role: .secondary) {
                    model.continueWithoutSyncing()
                }
            }
        }
    }
}
