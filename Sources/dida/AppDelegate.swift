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
                        rest: { [weak state] in state?.toggleRest() })

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleShowNotification(_:)),
            name: .init("com.blueDaydreaming725.dida.show"), object: nil)

        // 启动可见反馈
        let firstRun = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if firstRun { UserDefaults.standard.set(true, forKey: "hasLaunchedBefore") }
        banner.show(title: "滴答已启动",
                    subtitle: firstRun
                        ? "下次用药 \(clockString(state.nextMed)) · 点 Dock 图标打开面板"
                        : "点 Dock 图标打开面板",
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

    @objc private func showMainWindow() {
        if mainWindow == nil {
            guard let store, let state else { return }
            let controller = NSHostingController(
                rootView: RootPopoverView()
                    .padding(.top, 24) // 给透明标题栏的通行灯留位
                    .environmentObject(store)
                    .environmentObject(state))
            controller.sizingOptions = .preferredContentSize

            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.title = "滴答"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.cornerRadius = 16
            window.contentView?.layer?.masksToBounds = true
            window.center()
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
