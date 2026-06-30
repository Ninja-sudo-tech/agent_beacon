import Foundation

/// Wraps UserDefaults access for Agent Beacon preferences.
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private let suite = "com.agentbeacon.app"

    /// Minutes after which a `done` state auto-transitions to `idle`. 0 = disabled.
    var autoTransitionDoneMinutes: Int {
        get { defaults.integer(forKey: "\(suite).autoTransitionDoneMinutes") }
        set { defaults.set(newValue, forKey: "\(suite).autoTransitionDoneMinutes") }
    }

    /// Show the menu bar status item. Default: true.
    var showMenuBar: Bool {
        get {
            // UserDefaults returns false for missing keys, so treat "missing" as true
            if defaults.object(forKey: "\(suite).showMenuBar") == nil { return true }
            return defaults.bool(forKey: "\(suite).showMenuBar")
        }
        set { defaults.set(newValue, forKey: "\(suite).showMenuBar") }
    }

    /// Show the desktop floating window. Default: false.
    var showFloating: Bool {
        get { defaults.bool(forKey: "\(suite).showFloating") }
        set { defaults.set(newValue, forKey: "\(suite).showFloating") }
    }

    /// Floating window size preset: "small" | "medium" | "large" | "xlarge" | "xxlarge". Default: "medium".
    var floatingSize: String {
        get { defaults.string(forKey: "\(suite).floatingSize") ?? "medium" }
        set { defaults.set(newValue, forKey: "\(suite).floatingSize") }
    }

    /// Floating window layout: "vertical" | "horizontal". Default: "vertical".
    var floatingOrientation: String {
        get { defaults.string(forKey: "\(suite).floatingOrientation") ?? "vertical" }
        set { defaults.set(newValue, forKey: "\(suite).floatingOrientation") }
    }

    /// Show agent name labels beside circles in floating window. Default: true.
    var showFloatingLabels: Bool {
        get {
            if defaults.object(forKey: "\(suite).showFloatingLabels") == nil { return true }
            return defaults.bool(forKey: "\(suite).showFloatingLabels")
        }
        set { defaults.set(newValue, forKey: "\(suite).showFloatingLabels") }
    }
}
