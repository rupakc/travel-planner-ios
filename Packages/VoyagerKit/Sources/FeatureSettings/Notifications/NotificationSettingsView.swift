import DesignSystem
import L10n
import SharedUI
import SwiftUI
import UIKit
import VoyagerEnv
import VoyagerModel

/// You > Notifications. Hidden by its caller (the Settings row) without `features.notifications_api`; reached by a deep
/// route on an older backend it shows nothing but the title.
public struct NotificationSettingsView: View {
    @State private var model: NotificationSettingsModel
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @MainActor public init(env: AppEnvironment) {
        _model = State(initialValue: NotificationSettingsModel(env: env))
    }

    @MainActor init(model: NotificationSettingsModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            // VStack, not LazyVStack: lazy stacks hang hosted snapshot tests.
            VStack(alignment: .leading, spacing: Spacing.xl) {
                switch model.phase {
                case .loading:
                    ProgressView {
                        Text(verbatim: L10n.text(K.notifications.loading)).font(VFont.body(.footnote))
                    }
                    .frame(maxWidth: .infinity).padding(Spacing.xl)
                    .accessibilityIdentifier("notifications.loading")
                case .failed:
                    VStack(spacing: Spacing.sm) {
                        ErrorState(error: model.loadError) { Task { await model.load() } }
                        Text(verbatim: L10n.text(K.notifications.error.load))
                            .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                    }
                case .unavailable:
                    EmptyView()
                case .loaded:
                    form
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(SemanticColor.surface)
        .navigationTitle(L10n.text(K.notifications.title))
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            // Back from the system Settings: the permission may have changed.
            if phase == .active { Task { await model.refreshPermission() } }
        }
        .accessibilityIdentifier("notifications.root")
    }

    @ViewBuilder private var form: some View {
        Text(verbatim: L10n.text(K.notifications.intro))
            .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        PermissionStatusCard(
            state: model.permission, allow: { Task { await model.requestPermission() } }, openSettings: openSystemSettings)
        if model.pushUnavailable {
            note(L10n.text(K.mobile.notifSettings.pushUnavailable), icon: "info.circle", tid: "notifications.pushUnavailable")
        } else if model.showsNoDevices {
            note(L10n.text(K.notifications.noDevices), icon: "iphone.slash", tid: "notifications.noDevices")
        }
        categories
        quietHours
        dailyCap
        if model.saveFailed {
            Text(verbatim: L10n.text(K.notifications.error.save))
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("notifications.saveFailed")
        }
    }

    private func note(_ text: String, icon: String, tid: String) -> some View {
        Label {
            Text(verbatim: text).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(SemanticColor.textMuted)
        }
        .accessibilityIdentifier(tid)
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(model.categories, id: \.self) { category in
                        SettingsToggleRow(
                            title: Self.label(category), hint: Self.hint(category), tid: "notifications.category.\(category.rawValue)",
                            isOn: Binding(get: { model.isOn(category) }, set: { model.setCategory(category, on: $0) }))
                    }
                }
            }
        }
    }

    private var quietHours: some View {
        SettingsGroup(title: L10n.text(K.notifications.quiet.label)) {
            SettingsToggleRow(
                title: L10n.text(K.notifications.quiet.label), hint: L10n.text(K.notifications.quiet.hint),
                tid: "notifications.quiet.enabled",
                isOn: Binding(get: { model.settings.quietHours.enabled }, set: { model.setQuietEnabled($0) }))
            if model.settings.quietHours.enabled {
                clockRow(
                    title: L10n.text(K.notifications.quiet.start), tid: "notifications.quiet.start",
                    value: model.settings.quietHours.start
                ) { model.setQuietTimes(start: $0) }
                clockRow(
                    title: L10n.text(K.notifications.quiet.end), tid: "notifications.quiet.end", value: model.settings.quietHours.end
                ) { model.setQuietTimes(end: $0) }
            }
            Text(verbatim: model.settings.timezone.map { L10n.text(K.notifications.quiet.timezone, ["tz": $0]) }
                ?? L10n.text(K.notifications.quiet.noTimezone))
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("notifications.quiet.timezone")
        }
    }

    private func clockRow(title: String, tid: String, value: String, set: @escaping (String) -> Void) -> some View {
        DatePicker(
            selection: Binding(get: { QuietClock.date(value) }, set: { set(QuietClock.text($0)) }),
            displayedComponents: .hourAndMinute
        ) {
            Text(verbatim: title).font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier(tid)
    }

    private var dailyCap: some View {
        SettingsGroup(title: L10n.text(K.notifications.cap.label)) {
            Stepper(
                value: Binding(get: { model.settings.dailyCap }, set: { model.setCap($0) }),
                in: NotificationSettings.capRange
            ) {
                Text(verbatim: L10n.text(K.notifications.cap.value, ["count": String(model.settings.dailyCap)]))
                    .font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
            }
            .frame(minHeight: 44)
            .accessibilityLabel(L10n.text(K.notifications.cap.label))
            .accessibilityValue(L10n.text(K.notifications.cap.value, ["count": String(model.settings.dailyCap)]))
            .accessibilityIdentifier("notifications.cap")
            Text(verbatim: L10n.text(K.notifications.cap.hint))
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    static func label(_ category: NotificationCategory) -> String {
        switch category {
        case .priceDrops: L10n.text(K.notifications.categories.price_drops.label)
        case .tripReminders: L10n.text(K.notifications.categories.trip_reminders.label)
        case .morningBrief: L10n.text(K.notifications.categories.morning_brief.label)
        case .weather: L10n.text(K.notifications.categories.weather.label)
        case .nearby: L10n.text(K.notifications.categories.nearby.label)
        case .social: L10n.text(K.notifications.categories.social.label)
        case .quiz: L10n.text(K.notifications.categories.quiz.label)
        }
    }

    static func hint(_ category: NotificationCategory) -> String {
        switch category {
        case .priceDrops: L10n.text(K.notifications.categories.price_drops.hint)
        case .tripReminders: L10n.text(K.notifications.categories.trip_reminders.hint)
        case .morningBrief: L10n.text(K.notifications.categories.morning_brief.hint)
        case .weather: L10n.text(K.notifications.categories.weather.hint)
        case .nearby: L10n.text(K.notifications.categories.nearby.hint)
        case .social: L10n.text(K.notifications.categories.social.hint)
        case .quiz: L10n.text(K.notifications.categories.quiz.hint)
        }
    }
}

/// `HH:MM` (the wire form) to a `Date` on today's date in the device calendar and back, for the time pickers.
enum QuietClock {
    static func date(_ text: String, calendar: Calendar = .current, on day: Date = Date()) -> Date {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        let hour = parts.first ?? 0
        let minute = parts.count > 1 ? parts[1] : 0
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static func text(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
