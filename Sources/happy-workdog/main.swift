import AppKit

let app = NSApplication.shared
let delegate = WorkdogAppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
