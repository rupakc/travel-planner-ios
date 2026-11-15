import Foundation

extension ClientConfig {
    /// `features.journey`: the trip screens (Today) exist on this server. Without it a trip notification opens the trip
    /// detail instead (R8). Absent or wrong-typed counts as off.
    public var journeyAvailable: Bool {
        let flag = features["journey"]
        return flag?.bool == true || (flag?.int ?? 0) > 0
    }
}
