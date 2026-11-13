import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerEnv

/// The admin area: Users, Feedback and (when the backend has it) Analytics. Admins only.
public struct AdminRootView: View {
    @State private var model: AdminRootModel

    @MainActor public init(env: AppEnvironment) {
        _model = State(initialValue: AdminRootModel(env: env))
    }

    @MainActor init(model: AdminRootModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        Group {
            if model.isAdmin {
                content
            } else {
                Color.clear.accessibilityHidden(true)
            }
        }
        .background(SemanticColor.surface)
        .telemetryScreen("/admin")
        .task { await model.start() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(verbatim: L10n.text(K.account.admin.title))
                .font(VFont.display(.title2)).foregroundStyle(SemanticColor.text)
                .accessibilityAddTraits(.isHeader)
            tabBar
            switch model.selected {
            case .users: UsersView(model: model.users)
            case .feedback: FeedbackListView(model: model.feedback)
            case .analytics: AnalyticsView(model: model.analytics)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("admin.root")
    }

    private var tabBar: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(model.tabs) { tab in
                VChip(title: Self.title(tab), tid: "admin.tab.\(tab.rawValue)", selected: model.selected == tab) {
                    model.selected = tab
                }
            }
        }
    }

    static func title(_ tab: AdminRootModel.Tab) -> String {
        switch tab {
        case .users: L10n.text(K.account.admin.tabs.users)
        case .feedback: L10n.text(K.account.admin.tabs.feedback)
        case .analytics: L10n.text(K.adminTelemetry.tab)
        }
    }
}
