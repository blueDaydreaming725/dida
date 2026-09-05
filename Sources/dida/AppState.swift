import Foundation
import AppKit
import SwiftUI
import Combine

/// 核心状态机：1Hz 主计时器驱动，事件通知 UI 与图标。
@MainActor
final class AppState: ObservableObject {
    enum MedStep: Int {
        case first = 1
        case second = 2
    }

    enum SuspendKind {
        case mute
        case rest
    }

    // MARK: 已发布状态
    @Published private(set) var medStep: MedStep = .first
    @Published private(set) var nextMed: Date?
    @Published private(set) var nextBreak: Date?
    @Published private(set) var suspendedUntil: Date?
    @Published private(set) var suspendKind: SuspendKind?
    @Published private(set) var restStartedAt: Date?
    @Published private(set) var popupActive = false
    /// 图标/UI 状态变化时自增，供 Combine 订阅方感知
    @Published private(set) var visualRevision = 0

    let store: Store
    var onBanner: ((String, String, Int, String, Color) -> Void)?
    var onMedPopup: ((MedStep) -> Void)?
    var onClosePopup: (() -> Void)?

    private var tickTimer: Timer?
    /// 睡眠/静音期错过的宽限
    var missGrace: TimeInterval = 30 * 60
    let isDemo = CommandLine.arguments.contains("--demo")

    init(store: Store) {
        self.store = store
        startTimers()
    }

    var isSuspended: Bool { suspendedUntil != nil }

    // MARK: 启动

    private func startTimers() {
        let now = Date()
        nextMed = nextOccurrence(after: now + 15, times: store.medTimes) ?? now.addingTimeInterval(3600)
        nextBreak = now.addingTimeInterval(TimeInterval(store.workIntervalMinutes * 60))

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer

        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }

        if isDemo {
            nextMed = now.addingTimeInterval(5)
            nextBreak = now.addingTimeInterval(20)
        }
    }

    // MARK: 心跳

    private func tick() {
        let now = Date()

        if let until = suspendedUntil {
            if now >= until {
                if suspendKind == .rest {
                    endRest(early: false)
                } else {
                    resume(auto: true)
                }
            }
            return
        }

        if let med = nextMed, now >= med {
            if now.timeIntervalSince(med) > missGrace {
                // 错过太久，静默顺延
                nextMed = nextOccurrence(after: now + 60, times: store.medTimes) ?? now.addingTimeInterval(3600)
                bumpVisual()
            } else {
                fireMedPopup()
                return
            }
        }

        if let brk = nextBreak, now >= brk {
            nextBreak = now.addingTimeInterval(TimeInterval(store.workIntervalMinutes * 60))
            onBanner?("看远处 20 秒", "离开屏幕，眨眨眼 · 闭眼 20 秒也有效", 20, "eye", Dida.blue)
        }
    }

    // MARK: 用药流程

    private func fireMedPopup() {
        guard !popupActive else { return }
        popupActive = true
        nextMed = nil // 弹窗期间不再触发
        onMedPopup?(medStep)
        bumpVisual()
    }

    func medTaken() {
        let now = Date()
        switch medStep {
        case .first:
            medStep = .second
            let gap = isDemo ? 8.0 : TimeInterval(store.gapMinutes * 60)
            nextMed = now.addingTimeInterval(gap)
            onBanner?("已滴\(store.med1Name) ✓",
                      "\(store.gapMinutes) 分钟后滴\(store.med2Name)",
                      6, "drop.fill", Dida.indigo)
        case .second:
            medStep = .first
            nextMed = nextOccurrence(after: now + 60, times: store.medTimes) ?? now.addingTimeInterval(6 * 3600)
            onBanner?("本轮用药完成 ✓",
                      "下次 \(clockString(nextMed)) · 记得 4 周换新药",
                      6, "checkmark.circle.fill", Dida.indigo)
        }
        popupActive = false
        onClosePopup?()
        bumpVisual()
    }

    func medSnoozed() {
        nextMed = Date().addingTimeInterval(5 * 60)
        popupActive = false
        onClosePopup?()
        onBanner?("已延后 5 分钟", "\(clockString(nextMed)) 再提醒", 5, "clock", Dida.amber)
        bumpVisual()
    }

    /// 面板里的「现在滴药」
    func medNow() {
        if isSuspended { resume(auto: false, quiet: true) }
        nextMed = Date().addingTimeInterval(1)
    }

    // MARK: 护眼休息

    /// 面板里的「休息一下」（开始主动休息）
    func startRest() {
        if isSuspended && suspendKind == .rest { return }
        onClosePopup?()
        popupActive = false
        suspendKind = .rest
        suspendedUntil = Date().addingTimeInterval(TimeInterval(store.restMinutes * 60))
        restStartedAt = Date()
        onBanner?("休息中 🌿", "\(store.restMinutes) 分钟后自动回来 · ⌥⌘B 提前回来",
                  5, "leaf.fill", Dida.blue)
        bumpVisual()
    }

    /// 面板里的「再休 5 分钟」
    func extendRest(by minutes: Int = 5) {
        guard suspendKind == .rest, let until = suspendedUntil else { return }
        suspendedUntil = until.addingTimeInterval(TimeInterval(minutes * 60))
        onBanner?("好嘞，再休 \(minutes) 分钟", "闭眼、眨眼、看看窗外", 4, "leaf.fill", Dida.blue)
        bumpVisual()
    }

    func endRest(early: Bool) {
        let rested = restStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        resume(auto: false, quiet: true)
        onBanner?(early ? "已休息 \(formatDuration(rested))" : "休息好了",
                  early ? "闭眼眨眼也有效，继续加油" : "继续工作",
                  5, "figure.mind.and.body", Dida.blue)
    }

    // MARK: 静音（会议模式）

    func toggleMute() {
        if suspendKind == .mute {
            resume(auto: false)
        } else {
            suspend(minutes: store.muteMinutes, kind: .mute)
        }
    }

    func toggleRest() {
        if suspendKind == .rest {
            endRest(early: true)
        } else {
            startRest()
        }
    }

    private func suspend(minutes: Int, kind: SuspendKind) {
        onClosePopup?()
        popupActive = false
        suspendKind = kind
        suspendedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        if kind == .rest { restStartedAt = Date() }
        let hint = kind == .mute ? "⌥⌘M 提前恢复" : "⌥⌘B 提前回来"
        onBanner?(kind == .mute ? "已静音，安心开会" : "休息中 🌿",
                  "\(minutes) 分钟后自动恢复 · \(hint)", 6,
                  kind == .mute ? "moon.zzz.fill" : "leaf.fill",
                  kind == .mute ? Dida.amber : Dida.blue)
        bumpVisual()
    }

    private func resume(auto: Bool, quiet: Bool = false) {
        suspendedUntil = nil
        suspendKind = nil
        restStartedAt = nil

        let now = Date()
        if let med = nextMed, med <= now {
            nextMed = (now.timeIntervalSince(med) <= missGrace)
                ? now.addingTimeInterval(30)
                : nextOccurrence(after: now + 60, times: store.medTimes) ?? now.addingTimeInterval(3600)
        }
        nextBreak = now.addingTimeInterval(TimeInterval(store.workIntervalMinutes * 60))

        if !quiet {
            onBanner?("提醒已恢复", "下次用药 \(clockString(nextMed))", 5, "bell.fill", Dida.indigo)
        }
        bumpVisual()
    }

    // MARK: 设置联动

    func medTimesChanged() {
        guard !popupActive else { return }
        nextMed = nextOccurrence(after: Date() + 30, times: store.medTimes) ?? Date().addingTimeInterval(3600)
        bumpVisual()
    }

    func workIntervalChanged() {
        nextBreak = Date().addingTimeInterval(TimeInterval(store.workIntervalMinutes * 60))
    }

    private func bumpVisual() {
        visualRevision += 1
    }
}
