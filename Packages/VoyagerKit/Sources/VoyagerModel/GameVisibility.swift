import Foundation

/// Whether game wording (XP, badges, levels, boards, Play) may be shown. Hidden when the server turned the game
/// off (`features.game` false or absent) or the account's `hide_game` setting is on. An unreadable setting
/// (not loaded, failed to load) counts as hidden: showing game text to someone who opted out is the worse error.
public protocol GameVisibility: Sendable {
    /// `features.game`; nil while `/config` is unknown.
    var gameFeature: Bool? { get }
    /// The account's `hide_game`; nil when it could not be read.
    var hideGameSetting: Bool? { get }
}

extension GameVisibility {
    public var showsGame: Bool { gameFeature == true && hideGameSetting == false }
}

/// A fixed answer: previews, tests, and the default before an account setting is loaded.
public struct StaticGameVisibility: GameVisibility, Hashable {
    public var gameFeature: Bool?
    public var hideGameSetting: Bool?

    public init(gameFeature: Bool? = nil, hideGameSetting: Bool? = nil) {
        self.gameFeature = gameFeature
        self.hideGameSetting = hideGameSetting
    }

    public static let visible = StaticGameVisibility(gameFeature: true, hideGameSetting: false)
    public static let hidden = StaticGameVisibility(gameFeature: true, hideGameSetting: true)
    public static let unreadable = StaticGameVisibility()
}
