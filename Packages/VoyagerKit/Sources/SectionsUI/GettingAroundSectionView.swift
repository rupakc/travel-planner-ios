import SwiftUI
import VoyagerModel

/// Scaffold stub: replaced wholesale by the section task.
public struct GettingAroundSectionView: View {
    let data: JSONValue
    let ctx: SectionContext

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
    }

    public var body: some View { GenericSectionView(data: data, ctx: ctx) }
}
