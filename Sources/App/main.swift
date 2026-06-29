import AppKit

// Entry point — no @main, no @NSApplicationMain, to work with SPM
let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // hide from Dock
let delegate = AppDelegate()
app.delegate = delegate
app.run()
