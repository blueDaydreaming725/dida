import AppKit

@main
@MainActor
struct DidaApp {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular) // Dock 常驻，无菜单栏图标
        app.run()
    }
}
