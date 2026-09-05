import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var store: Store?
    private var state: AppState?
    private var popover: NSPopover?
    private var medPopup: MedPopupController?
    private var banner: BannerController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            banner.show(title: "滴答已启动",
                        subtitle: "下次用药 \(clockString(state.nextMed)) · 图标就在菜单栏",
                        seconds: 8, icon: "eye", tint: Dida.indigo)
        }
    }

    // MARK: 菜单栏图标

    private func statusImage() -> NSImage? {
        let name: String
        switch (state?.popupActive, state?.isSuspended) {
        case (true, _): name = "drop.fill"
        case (_, true): name = "eye.slash"
        default: name = "eye"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "滴答 · 用药与护眼提醒")
        image?.size = NSSize(width: 18, height: 18)
        return image
    }

    private func updateIcon() {
        statusItem?.button?.image = statusImage()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = statusImage()
        item.button?.image?.size = NSSize(width: 18, height: 18)
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc private func statusClicked() {
        guard let event = NSApp.currentEvent else { togglePopover(); return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            togglePopover()
        }
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
        self.popover = popover
    }

    private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
