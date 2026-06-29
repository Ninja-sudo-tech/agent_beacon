import Foundation

/// Wraps UserDefaults access for Agent Beacon preferences.
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private let suite = "com.agentbeacon.app"

    /// Minutes after which a `done` state auto-transitions to `idle`.
    /// 0 means disabled.
    var autoTransitionDoneMinutes: Int {
        get { defaults.integer(forKey: "\(suite).autoTransitionDoneMinutes") }
        set { defaults.set(newValue, forKey: "\(suite).autoTransitionDoneMinutes") }
    }
}
