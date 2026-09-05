import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let bundleID = "com.blueDaydreaming725.dida"
    private var statusItem: NSStatusItem?
    private var store: Store?
    private var state: AppState?
    private var popover: NSPopover?
    private var medPopup: MedPopupController?
    private var banner: BannerController?
    private var cancellables = Set<AnyCancellable>()
    private var lastPopoverCloseAt = Date.distantPast
    private let myPID = ProcessInfo.processInfo.processIdentifier

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 二次启动：已有实例在运行时，让老实例亮相，新实例退出
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

        setupStatusItem()
        setupPopover(store: store, state: state)

        HotKeys.install(mute: { [weak state] in state?.toggleMute() },
                        rest: { [weak state] in state?.toggleRest() })

        state.$visualRevision
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
        updateIcon()

        // 已有实例收到“新实例启动”通知后亮相
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(showRunningBanner(_:)),
            name: .init("com.blueDaydreaming725.dida.show"), object: nil)

        // 每次启动都给可见反馈（无 Dock、无窗口，启动本身必须“看得见”）
        let firstRun = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if firstRun { UserDefaults.standard.set(true, forKey: "hasLaunchedBefore") }
        banner.show(title: "滴答已启动",
                    subtitle: firstRun
                        ? "下次用药 \(clockString(state.nextMed)) · HW 图标就在菜单栏"
                        : "HW 图标就在菜单栏右上角",
                    seconds: firstRun ? 8 : 4, icon: "drop.fill", tint: Dida.indigo)
    }

    @objc private func showRunningBanner(_ notification: Notification) {
        guard notification.object as? String != "\(myPID)" else { return }
        banner?.show(title: "滴答已在运行中",
                     subtitle: "图标就在菜单栏右上角 · 单击 HW 打开面板",
                     seconds: 5, icon: "drop.fill", tint: Dida.indigo)
    }

    // MARK: 菜单栏图标
    // macOS 26 Liquid Glass 菜单栏只可靠渲染 template 图（黑 + alpha，系统自动着色），
    // 彩色非模板图会直接消失——所以这里全部用模板图；彩色 HW 渐变保留在面板头部。

    private func statusImage() -> NSImage? {
        switch (state?.popupActive, state?.suspendKind) {
        case (true, _): // 弹窗等待确认中
            return NSImage(systemSymbolName: "eyedropper", accessibilityDescription: Self.iconTip)
        case (_, .rest): // 休息中
            return NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: Self.iconTip)
        case (_, .mute): // 静音中
            return NSImage(systemSymbolName: "moon.zzz.fill", accessibilityDescription: Self.iconTip)
        default: // 正常提醒：HW 品牌字标
            return Self.hwTemplateIcon()
        }
    }

    private static let iconTip = "滴答 · 用药与护眼提醒（HW）"

    /// HW 品牌字标，模板渲染（黑 + alpha）
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

    private func updateIcon() {
        statusItem?.button?.image = statusImage()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 36)
        item.button?.image = statusImage()
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc private func statusClicked() {
        guard let event = NSApp.currentEvent else { togglePopover(); return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
            return
        }
        // 双击只算一次：连点不再出现“开了又关”，面板保持打开
        if event.type == .leftMouseUp && event.clickCount > 1 { return }
        togglePopover()
    }

    private func showMenu() {
        guard let state, let store else { return }
        let menu = NSMenu()
        let muteTitle = state.isSuspended ? "恢复提醒" : "静音 \(store.muteMinutes) 分钟"
        menu.addItem(withTitle: muteTitle, action: #selector(menuMute), keyEquivalent: "")
        menu.addItem(withTitle: state.suspendKind == .rest ? "休息回来" : "休息一下",
                     action: #selector(menuRest), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出滴答", action: #selector(menuQuit), keyEquivalent: "")
        for item in menu.items { item.target = self }
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func menuMute() { state?.toggleMute() }
    @objc private func menuRest() { state?.toggleRest() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: 面板

    private func setupPopover(store: Store, state: AppState) {
        let controller = NSHostingController(
            rootView: RootPopoverView()
                .environmentObject(store)
                .environmentObject(state))
        controller.sizingOptions = .preferredContentSize
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 330, height: 360)
        popover.delegate = self
        self.popover = popover
    }

    private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // 刚因点击图标自身被 transient 关闭：这次点击就是“关闭”，不要闪开
        guard Date().timeIntervalSince(lastPopoverCloseAt) > 0.25 else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        lastPopoverCloseAt = Date()
    }
}
