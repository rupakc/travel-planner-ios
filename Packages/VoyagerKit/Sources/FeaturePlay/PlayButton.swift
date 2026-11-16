import SharedUI
import SwiftUI

/// A `VButton` that stays a tidy pill at accessibility text sizes: its last-resort wrapping turns a capsule into a
/// circle, so there the label drops its icon and is held at the standard size, where Play's labels fit on one line.
struct PlayButton: View {
    let title: String
    let tid: String
    let role: VButtonRole
    let systemImage: String?
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    init(
        _ title: String, tid: String, role: VButtonRole = .primary, systemImage: String? = nil, action: @escaping () -> Void
    ) {
        self.title = title
        self.tid = tid
        self.role = role
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            VButton(title, tid: tid, role: role, action: action).dynamicTypeSize(...DynamicTypeSize.large)
        } else {
            VButton(title, tid: tid, role: role, systemImage: systemImage, action: action)
        }
    }
}
