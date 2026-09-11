import Foundation
import AppKit
import SwiftUI
import Combine

/// 核心状态机：1Hz 主计时器驱动，事件通知 UI 与图标。
///
/// 休息语义（TODO ①④⑤⑥⑦ 落地版）：
/// - 「看远处」弹窗只是提醒，不点就留着；唯一有效的休息凭证是 ⌥⌘B；
/// - 滴眼药水 = 一次休息（计时刷新 + 记录）；
/// - 熄屏 ≥2 分钟 = 一次休息；护眼计时按实际亮屏时长驱动；
/// - ⌥⌘S 暂停（人不在电脑前），⌥⌘M 静音（人在但开会）。
@MainActor
final class AppState: ObservableObject {
    enum MedStep: Int {
        case first = 1
        case second = 2
    }

    enum SuspendKind {
        case mute    // 会议静音：手动恢复
        case rest    // 主动休息：到时自动回来
        case paused  // 人不在电脑前：手动恢复
    }

    // MARK: 已发布状态
    @Published private(set) var medStep: MedStep = .first
    @Published private(set) var nextMed: Date?
    @Published private(set) var nextBreak: Date?
    @Published private(set) var suspendedUntil: Date?
    @Published private(set) var suspendKind: SuspendKind?
    @Published private(set) var popupActive = false
    @Published private(set) var breakPopupActive = false
    @Published private(set) var screenAsleep = false
    @Published private(set) var visualRevision = 0

    let store: Store
    let restStore: RestStore

    var onBanner: ((String, String, Int, String, Color) -> Void)?
    var onMedPopup: ((MedStep) -> Void)?
    var onClosePopup: (() -> Void)?
    var onBreakPopup: ((Bool) -> Void)?          // 参数 = 是否合并用药预告
    var onCloseBreakPopup: (() -> Void)?
    var onWeeklyReport: (() -> Void)?

    private var tickTimer: Timer?
    private var screenSleepStart: Date?
    private var breakPopupRestoreAfterWake = false
    private var breakPopupWasMerged = false
    private var restStartedAt: Date?
    var missGrace: TimeInterval = 30 * 60
    let isDemo = CommandLine.arguments.contains("--demo")

    init(store: Store, restStore: RestStore) {
        self.store = store
        self.restStore = restStore
        startTimers()
    }

    var isSuspended: Bool { suspendKind != nil }

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

        // 系统唤醒兜底（错过宽限处理）
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        // 显示器熄灭/点亮（TODO ⑤）
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.screensSleep() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.screensWake() }
        }

        if isDemo {
            nextMed = now.addingTimeInterval(5)
            nextBreak = now.addingTimeInterval(20)
        }
    }

    // MARK: 心跳

    private func tick() {
        let now = Date()
        checkWeeklyReport(now)

        if screenAsleep { return }

        // 休息倒计时：到点自动回来
        if suspendKind == .rest, let until = suspendedUntil, now >= until {
            endRest(early: false)
            return
        }
        // 静音/暂停：冻结一切
        if suspendKind == .mute || suspendKind == .paused { return }
        // 用药弹窗开着：护眼不叠窗
        if popupActive { return }
        // 护眼弹窗开着：一直等用户处理（⌥⌘B 真休息 / 「忙」顺延）
        if breakPopupActive { return }

        // 用药到点
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

        // 护眼到点（若 10 分钟内要滴药，弹合并预告）
        if let brk = nextBreak, now >= brk {
            nextBreak = nil // 确认/休息后才重新计时
            breakPopupActive = true
            breakPopupWasMerged = isMedImminent(now)
            onBreakPopup?(breakPopupWasMerged)
            bumpVisual()
            return
        }
    }

    /// 距下次用药是否不足 10 分钟
    private func isMedImminent(_ now: Date) -> Bool {
        (nextMed?.timeIntervalSince(now) ?? .infinity) <= 600
    }

    // MARK: 周报（TODO ②：每周六上午自动弹一次）

    private func checkWeeklyReport(_ now: Date) {
        // 补漏语义：只要运行时刻已越过本周六 09:00，且本期还没看过，就在任意一天补看
        let end = lastReportEnd(from: now)
        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: end)
        let key = "\(comps.yearForWeekOfYear ?? 0)-\(comps.weekOfYear ?? 0)"
        guard UserDefaults.standard.string(forKey: "lastWeeklyReport") != key else { return }
        UserDefaults.standard.set(key, forKey: "lastWeeklyReport")
        onWeeklyReport?()
    }

    // MARK: 用药流程

    private func fireMedPopup() {
        guard !popupActive else { return }
        popupActive = true
        nextMed = nil // 弹窗期间不再触发
        // 护眼弹窗给用药让位（滴药优先且本身算休息）
        if breakPopupActive {
            breakPopupActive = false
            onCloseBreakPopup?()
        }
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
            // TODO ④：滴药即休息——刷新护眼计时 + 记录（计 1 分钟）
            nextBreak = now.addingTimeInterval(TimeInterval(store.workIntervalMinutes * 60))
            restStore.add(start: now.addingTimeInterval(-60), end: now, kind: .medication)
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

    // MARK: 护眼休息（⌥⌘B 是唯一有效休息凭证）

    /// 护眼弹窗上的「忙」：没空休息，5 分钟后再提
    func deferBreak() {
        breakPopupActive = false
        onCloseBreakPopup?()
        nextBreak = Date().addingTimeInterval(5 * 60)
        bumpVisual()
    }

    /// 面板里的「休息一下」/ ⌥⌘B：真正休息开始
    func startRest() {
        if suspendKind == .rest { return }
        closeAllPopups()
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
        if let start = restStartedAt, rested >= 15 {
            restStore.add(start: start, end: Date(), kind: .manual)
        }
        resume(auto: false, quiet: true)
        onBanner?(early ? "已休息 \(formatDuration(rested))" : "休息好了",
                  early ? "闭眼眨眼也有效，继续加油" : "继续工作",
                  5, "figure.mind.and.body", Dida.blue)
    }

    // MARK: 静音（会议，手动恢复）/ 暂停（人不在，手动恢复）

    func toggleMute() {
        if suspendKind == .mute {
            resume(auto: false)
        } else {
            suspendMute()
        }
    }

    func toggleRest() {
        if suspendKind == .rest {
            endRest(early: true)
        } else {
            startRest()
        }
    }

    /// ⌥⌘S：暂停（人不在电脑前）——TODO ⑦
    func togglePause() {
        if suspendKind == .paused {
            resume(auto: false, quiet: true)
            onBanner?("欢迎回来", "计时已恢复", 4, "play.fill", Dida.indigo)
        } else {
            suspendPaused()
        }
    }

    private func suspendMute() {
        closeAllPopups()
        suspendKind = .mute
        suspendedUntil = nil
        onBanner?("已静音，安心开会", "不会自动恢复 · ⌥⌘M 或「恢复提醒」结束", 6,
                  "moon.zzz.fill", Dida.amber)
        bumpVisual()
    }

    private func suspendPaused() {
        closeAllPopups()
        suspendKind = .paused
        suspendedUntil = nil
        onBanner?("已暂停", "人不在电脑前 · ⌥⌘S 继续", 5,
                  "pause.fill", Dida.indigo)
        bumpVisual()
    }

    private func closeAllPopups() {
        if popupActive {
            // 药窗被打断：标记待重弹，恢复后 30 秒内补弹
            nextMed = Date()
            popupActive = false
            onClosePopup?()
        }
        if breakPopupActive {
            breakPopupActive = false
            onCloseBreakPopup?()
        }
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
        // 恢复即重新计时：休息/暂停期间挂起的护眼提醒一并清掉
        nextBreak = now.addingTimeInterval(TimeInterval(store.workIntervalMinutes * 60))

        if !quiet {
            onBanner?("提醒已恢复", "下次用药 \(clockString(nextMed))", 5, "bell.fill", Dida.indigo)
        }
        bumpVisual()
    }

    // MARK: 熄屏（TODO ⑤）

    func screensSleep() {
        guard !screenAsleep else { return }
        screenAsleep = true
        screenSleepStart = Date()
        // 休息中被熄屏：按已休息记录并结束休息态
        if suspendKind == .rest, let start = restStartedAt, Date().timeIntervalSince(start) >= 15 {
            restStore.add(start: start, end: Date(), kind: .manual)
        }
        let breakWasWaiting = breakPopupActive
        closeAllPopups()
        if breakWasWaiting { breakPopupRestoreAfterWake = true }
        suspendedUntil = nil
        suspendKind = nil
        restStartedAt = nil
        bumpVisual()
    }

    func screensWake() {
        guard screenAsleep else { return }
        screenAsleep = false
        let start = screenSleepStart
        screenSleepStart = nil
        let elapsed = start.map { Date().timeIntervalSince($0) } ?? 0
        defer { bumpVisual(); tick() }

        guard elapsed >= RestStore.screenOffRestThreshold, let start else {
            // 短熄屏：计时顺延；被收起的护眼弹窗恢复
            nextBreak = nextBreak?.addingTimeInterval(elapsed)
            nextMed = nextMed?.addingTimeInterval(elapsed) ?? nextMed
            if breakPopupRestoreAfterWake {
                breakPopupRestoreAfterWake = false
                breakPopupActive = true
                breakPopupWasMerged = isMedImminent(Date())
                onBreakPopup?(breakPopupWasMerged)
            }
            return
        }
        // 长熄屏 = 休息：护眼清零重算 + 记录；用药保持绝对时间点（错过宽限兜底）
        breakPopupRestoreAfterWake = false
        restStore.add(start: start, end: start.addingTimeInterval(elapsed), kind: .screenOff)
        nextBreak = Date().addingTimeInterval(TimeInterval(store.workIntervalMinutes * 60))
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
