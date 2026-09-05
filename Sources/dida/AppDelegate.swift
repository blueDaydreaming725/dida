import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let bundleID = "com.blueDaydreaming725.dida"
    private var store: Store?
    private var state: AppState?
    private var medPopup: MedPopupController?
    private var banner: BannerController?
    private var cancellables = Set<AnyCancellable>()
    private var mainWindow: NSWindow?
    private var statusItem: NSStatusItem? // 可选：设置里开启
    private let myPID = ProcessInfo.processInfo.processIdentifier

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 二次启动：让已有实例把面板亮出来，新实例退出
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
            .filter { $0.processIdentifier != myPID }
        if !others.isEmpty && Bundle.main.bundlePath.hasSuffix(".app") {
            DistributedNotificationCenter.default().post(
                name: .init("com.blueDaydreaming725.dida.show"), object: "\(myPID)")
            exit(0)
        }

        let store = Store()
        let state = AppState(store: store)
        let banner = BannerController()
        let medPopup = MedPopupController(
            onTaken: { [weak state] in state?.medTaken() },
            onSnooze: { [weak state] in state?.medSnoozed() })

        state.onBanner = { [weak banner] title, subtitle, seconds, icon, tint in
            banner?.show(title: title, subtitle: subtitle, seconds: seconds, icon: icon, tint: tint)
        }
        state.onMedPopup = { [weak medPopup, weak store] step in
            if store?.playSound ?? true {
                NSSound(named: "Glass")?.play()
            }
            medPopup?.show(step: step,
                           med1: store?.med1Name ?? "富马",
                           med2: store?.med2Name ?? "聚乙二醇",
                           gapMinutes: store?.gapMinutes ?? 5)
        }
        state.onClosePopup = { [weak medPopup] in medPopup?.dismiss() }

        self.store = store
        self.state = state
        self.banner = banner
        self.medPopup = medPopup

        HotKeys.install(mute: { [weak state] in state?.toggleMute() },
                        rest: { [weak state] in state?.toggleRest() },
                        panel: { [weak self] in self?.toggleMainWindow() })

        // 菜单栏图标开关
        updateMenuBarIcon()
        store.$showMenuBarIcon
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMenuBarIcon() }
            .store(in: &cancellables)

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleShowNotification(_:)),
            name: .init("com.blueDaydreaming725.dida.show"), object: nil)

        // 启动可见反馈
        let firstRun = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if firstRun { UserDefaults.standard.set(true, forKey: "hasLaunchedBefore") }
        banner.show(title: "滴答已启动",
                    subtitle: firstRun
                        ? "下次用药 \(clockString(state.nextMed)) · ⌥⌘P 或点 Dock 图标打开面板"
                        : "⌥⌘P 或点 Dock 图标打开面板",
                    seconds: firstRun ? 8 : 4, icon: "drop.fill", tint: Dida.indigo)
        if firstRun {
            showMainWindow()
        }
    }

    @objc private func handleShowNotification(_ notification: Notification) {
        guard notification.object as? String != "\(myPID)" else { return }
        showMainWindow()
        banner?.show(title: "滴答已在运行中", subtitle: "面板已为你打开", seconds: 4,
                     icon: "drop.fill", tint: Dida.indigo)
    }

    // MARK: 主窗口（面板）

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // 关窗后提醒继续
    }

    func toggleMainWindow() {
        if let window = mainWindow, window.isVisible, window.isKeyWindow {
            window.performClose(nil)
        } else {
            showMainWindow()
        }
    }

    @objc private func showMainWindow() {
        if mainWindow == nil {
            guard let store, let state else { return }
            let controller = NSHostingController(
                rootView: ScrollView {
                    RootPopoverView()
                        .padding(.top, 44) // 透明标题栏 + 通行灯
                }
                .frame(width: 330)
                .scrollIndicators(.hidden)
                .environmentObject(store)
                .environmentObject(state))
            controller.sizingOptions = []
            let fitting = controller.view.fittingSize
            let width = max(330, fitting.width)
            let height = max(480, fitting.height)

            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "滴答"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false

            // 容器层裁出四角大圆角（系统窗口自带圆角太小）
            let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
            container.wantsLayer = true
            container.layer?.cornerRadius = 22
            container.layer?.masksToBounds = true
            controller.view.frame = container.bounds
            controller.view.autoresizingMask = [.width, .height]
            container.addSubview(controller.view)
            window.contentView = container
            window.center()
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: 菜单栏图标（可选，模板渲染）

    private func updateMenuBarIcon() {
        guard let store else { return }
        if store.showMenuBarIcon {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: 36)
                item.button?.image = statusImage()
                item.button?.target = self
                item.button?.action = #selector(statusClicked)
                item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                statusItem = item
            }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func statusImage() -> NSImage? {
        // Liquid Glass 菜单栏只渲染 template 图（黑 + alpha）
        switch (state?.popupActive, state?.suspendKind) {
        case (true, _):
            return NSImage(systemSymbolName: "eyedropper", accessibilityDescription: Self.iconTip)
        case (_, .rest):
            return NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: Self.iconTip)
        case (_, .mute):
            return NSImage(systemSymbolName: "moon.zzz.fill", accessibilityDescription: Self.iconTip)
        default:
            return Self.hwTemplateIcon()
        }
    }

    private static let iconTip = "滴答 · 用药与护眼提醒（HW）"

    private static func hwTemplateIcon() -> NSImage {
        let text = "HW"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .heavy),
            .kern: CGFloat(-0.6),
            .foregroundColor: NSColor.black,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let width = ceil(textSize.width) + 2
        let height = ceil(textSize.height) + 1
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            (text as NSString).draw(at: NSPoint(x: 1, y: 0), withAttributes: attrs)
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func statusClicked() {
        guard let event = NSApp.currentEvent else { toggleMainWindow(); return }
        if event.type == .leftMouseUp && event.clickCount > 1 { return }
        toggleMainWindow()
    }
}
