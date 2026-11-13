import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// User list. On iPad the list is the content column and the selected user fills the detail column;
/// on iPhone the detail opens as a sheet.
struct UsersView: View {
    let model: UsersModel
    @State private var selectedName: String?
    @State private var showCreate = false
    @State private var resetTarget: AdminUser?
    @State private var confirmTarget: AdminUser?
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var selected: AdminUser? { model.users.first { $0.username == selectedName } }
    private var regular: Bool { AdaptiveLayout.isRegular(sizeClass) }

    var body: some View {
        Group {
            if regular {
                HStack(alignment: .top, spacing: Spacing.lg) {
                    listColumn.frame(maxWidth: 380)
                    detailColumn.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                listColumn
            }
        }
        .task { if !model.loaded { await model.load() } }
        .sheet(isPresented: $showCreate) { CreateUserSheet(model: model) { showCreate = false } }
        .sheet(isPresented: Binding(get: { resetTarget != nil }, set: { if !$0 { resetTarget = nil } })) {
            if let user = resetTarget {
                ResetPasswordSheet(model: model, username: user.username, isSelf: model.isSelf(user)) { resetTarget = nil }
            }
        }
        .sheet(isPresented: Binding(get: { !regular && selected != nil }, set: { if !$0 { selectedName = nil } })) {
            if let user = selected {
                UserDetail(model: model, user: user, reset: { resetTarget = user }, confirm: { confirmTarget = user })
                    .presentationDetents([.medium, .large])
            }
        }
        .confirmationDialog(
            L10n.text(K.mobile.admin.deactivateConfirm, ["name": confirmTarget?.username ?? ""]),
            isPresented: Binding(get: { confirmTarget != nil }, set: { if !$0 { confirmTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.text(K.account.admin.users.deactivate), role: .destructive) {
                if let user = confirmTarget { Task { await model.deactivate(user) } }
                confirmTarget = nil
            }
            Button(L10n.text(K.account.admin.common.cancel), role: .cancel) { confirmTarget = nil }
        }
    }

    private var listColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text(verbatim: L10n.text(K.account.admin.users.count, count: model.users.count))
                        .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                    Spacer(minLength: Spacing.sm)
                    VButton(L10n.text(K.account.admin.users.create), tid: "admin.users.create", role: .tonal) { showCreate = true }
                }
                if let name = model.resetDone {
                    Text(verbatim: L10n.text(K.account.admin.reset.success, ["username": name]))
                        .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                        .accessibilityIdentifier("admin.reset.done")
                }
                if let error = model.error {
                    ErrorState(error: error) { Task { await model.load() } }
                } else if model.loading && !model.loaded {
                    Text(verbatim: L10n.text(K.account.admin.common.loading)).foregroundStyle(SemanticColor.textMuted)
                } else {
                    // A plain VStack: admin lists are short, and hosted snapshots cannot lay out lazy stacks.
                    VStack(spacing: Spacing.sm) {
                        ForEach(model.users, id: \.username) { user in row(user) }
                    }
                }
            }
            .padding(.bottom, Spacing.xl)
        }
        .refreshable { await model.load() }
        .accessibilityIdentifier("admin.users.list")
    }

    private func row(_ user: AdminUser) -> some View {
        Button { selectedName = user.username } label: {
            VCard {
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(verbatim: user.username).font(VFont.body(.headline)).foregroundStyle(SemanticColor.text)
                        if let email = user.email, !email.isEmpty {
                            Text(verbatim: email).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                        }
                    }
                    Spacer(minLength: Spacing.sm)
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text(verbatim: UserDetail.roleTitle(user)).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                        Text(verbatim: UserDetail.statusTitle(user)).font(VFont.body(.caption))
                            .foregroundStyle(user.isActive == false ? SemanticColor.destructive : SemanticColor.text)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Radius.itemCard)
                    .stroke(selectedName == user.username && regular ? SemanticColor.primary : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("admin.users.row")
    }

    @ViewBuilder private var detailColumn: some View {
        if let user = selected {
            ScrollView {
                UserDetail(model: model, user: user, reset: { resetTarget = user }, confirm: { confirmTarget = user })
            }
        } else {
            EmptyState(icon: "person.2", title: L10n.text(K.mobile.admin.selectUser))
        }
    }
}

/// One user's facts and actions.
struct UserDetail: View {
    let model: UsersModel
    let user: AdminUser
    let reset: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(verbatim: user.username).font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
            fact(K.account.admin.table.email, user.email)
            fact(K.account.admin.table.role, Self.roleTitle(user))
            fact(K.account.admin.table.status, Self.statusTitle(user))
            fact(K.account.admin.table.created, user.createdAt.map { String($0.prefix(10)) })
            if model.isSelf(user) {
                Text(verbatim: L10n.text(K.account.admin.users.resetOwnHint))
                    .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
            }
            VButton(
                model.isSelf(user) ? L10n.text(K.account.admin.users.resetOwn) : L10n.text(K.account.admin.users.reset),
                tid: "admin.users.reset", role: .secondary, action: reset)
            if model.canDeactivate(user) {
                VButton(L10n.text(K.account.admin.users.deactivate), tid: "admin.users.deactivate", role: .destructive, action: confirm)
                    .disabled(model.busy.contains(user.username))
            }
            if model.canReactivate(user) {
                VButton(L10n.text(K.account.admin.users.reactivate), tid: "admin.users.reactivate") {
                    Task { await model.reactivate(user) }
                }
                .disabled(model.busy.contains(user.username))
            }
            if let error = model.error {
                Text(verbatim: ErrorCopy.message(kind: error.presentationKind, detail: error.userFacingDetail))
                    .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.destructive)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("admin.users.detail")
    }

    private func fact(_ label: LKey, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: L10n.text(label)).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            Text(verbatim: (value?.isEmpty == false ? value : nil) ?? "-").font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
        }
    }

    static func roleTitle(_ user: AdminUser) -> String {
        user.isAdmin == true ? L10n.text(K.account.admin.role.admin) : L10n.text(K.account.admin.role.user)
    }

    static func statusTitle(_ user: AdminUser) -> String {
        user.isActive == false ? L10n.text(K.account.admin.status.inactive) : L10n.text(K.account.admin.status.active)
    }
}
