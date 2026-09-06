import AppKit
import SwiftUI

/// 置顶小窗基类：无边框、不抢键盘焦点、跨全屏 Space，出现时从上滑入淡出。
class TopPanel: NSPanel {
    init(width: CGFloat, content: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: 120),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        hasShadow = false
        contentView = content
    }

    override var canBecomeKey: Bool { true }

    /// 顶部居中放置，yPad 为距屏幕顶部的间距
    func place(yPad: CGFloat) {
        guard let screen = NSScreen.main, let content = contentView else { return }
        let size = content.fittingSize
        setContentSize(size)
        let frame = screen.visibleFrame
        setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                               y: frame.maxY - size.height - yPad))
    }

    func present(yPad: CGFloat) {
        place(yPad: yPad)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
        guard animated else {
            orderOut(nil); close(); completion?(); return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.close()
            completion?()
        })
    }
}

// MARK: - 用药强制确认弹窗

@MainActor
final class MedPopupController {
    private var panel: TopPanel?
    var onTaken: () -> Void
    var onSnooze: () -> Void

    init(onTaken: @escaping () -> Void, onSnooze: @escaping () -> Void) {
        self.onTaken = onTaken
        self.onSnooze = onSnooze
    }

    func show(step: AppState.MedStep, med1: String, med2: String, gapMinutes: Int) {
        dismiss(instant: true)
        let isFirst = step == .first
        let tint: Color = isFirst ? Dida.indigo : Dida.violet // 富马=蓝，聚乙二醇=紫
        let icon = isFirst ? "eyedropper" : "drop.fill"
        let title = isFirst ? "该滴「\(med1)」了" : "该滴「\(med2)」了"
        let subtitle = isFirst
            ? "第 1 步 · 共 2 步 · \(gapMinutes) 分钟后滴\(med2)"
            : "第 2 步 · 共 2 步 · 滴完本轮结束"
        let view = MedPopupView(
            icon: icon,
            iconTint: tint,
            title: title,
            subtitle: subtitle,
            onTaken: { [weak self] in self?.onTaken() },
            onSnooze: { [weak self] in self?.onSnooze() }
        )
        let hosting = NSHostingView(rootView: view)
        let panel = TopPanel(width: 410, content: hosting)
        self.panel = panel
        panel.present(yPad: 96) // 上方给横幅留位置
    }

    func dismiss(instant: Bool = false) {
        guard let panel else { return }
        self.panel = nil
        panel.dismiss(animated: !instant)
    }
}

// MARK: - 轻量横幅（自动消失，可点击提前关掉）

@MainActor
final class BannerController {
    private var panel: TopPanel?
    private var autoCloseTimer: Timer?

    func show(title: String, subtitle: String, seconds: Int, icon: String, tint: Color,
              onBusy: (() -> Void)? = nil) {
        closeNow()
        let view = BannerView(icon: icon, tint: tint, title: title, subtitle: subtitle,
                              seconds: seconds, onBusy: onBusy) { [weak self] in
            self?.closeNow()
        }
        let panel = TopPanel(width: 340, content: NSHostingView(rootView: view))
        self.panel = panel
        panel.level = .popUpMenu // 比用药弹窗低一层
        panel.present(yPad: 12)

        let timer = Timer(timeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.closeNow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoCloseTimer = timer
    }

    func closeNow() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        guard let panel else { return }
        self.panel = nil
        panel.dismiss(animated: true)
    }
}

// MARK: - 护眼确认弹窗控制器（不确认就一直留着）

@MainActor
final class BreakPopupController {
    private var panel: TopPanel?
    var onConfirm: () -> Void
    var onBusy: () -> Void

    init(onConfirm: @escaping () -> Void, onBusy: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onBusy = onBusy
    }

    func show() {
        dismiss(instant: true)
        let view = BreakPopupView(onConfirm: { [weak self] in self?.onConfirm() },
                                  onBusy: { [weak self] in self?.onBusy() })
        let panel = TopPanel(width: 400, content: NSHostingView(rootView: view))
        self.panel = panel
        panel.present(yPad: 96)
    }

    func dismiss(instant: Bool = false) {
        guard let panel else { return }
        self.panel = nil
        panel.dismiss(animated: !instant)
    }
}
