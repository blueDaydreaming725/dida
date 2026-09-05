import AppKit

@main
@MainActor
struct DidaApp {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // 无 Dock 图标
        app.run()
    }
}
