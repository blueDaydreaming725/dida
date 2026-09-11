import Foundation

/// 一条休息记录。kind: manual=⌥⌘B 主动休息 · medication=滴眼药水(计 1 分钟) · screenOff=熄屏
struct RestRecord: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case manual, medication, screenOff
    }

    var id: UUID = UUID()
    var start: Date
    var end: Date
    var kind: Kind
}

struct DayStat: Identifiable, Equatable {
    var id: Date { day }
    let day: Date
    let restSeconds: TimeInterval
    let manualCount: Int
    let medCount: Int
}

struct WeeklySummary {
    let start: Date
    let end: Date
    let days: [DayStat]          // 固定 7 天，旧→新
    let restSeconds: TimeInterval
    let manualCount: Int
    let medCount: Int
    let prevRestSeconds: TimeInterval
    let prevManualCount: Int
    let prevMedCount: Int

    var restHoursText: String {
        let total = Int(restSeconds) / 60
        if total >= 60 { return "\(total / 60) 小时 \(total % 60) 分" }
        return "\(total) 分钟"
    }
}

/// 休息记录存储：JSON 文件持久化，保留 90 天。周报与统计的数据源。
@MainActor
final class RestStore: ObservableObject {
    private let fileURL: URL
    private var records: [RestRecord] = []

    /// 滴眼药水按固定 1 分钟计入休息时长
    static let medicationCreditSeconds: TimeInterval = 60
    /// 熄屏超过该阈值才视为一次休息
    static let screenOffRestThreshold: TimeInterval = 120

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dida", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("rest-records.json")
        load()
    }

    func add(start: Date, end: Date, kind: RestRecord.Kind) {
        guard end > start else { return }
        records.append(RestRecord(start: start, end: end, kind: kind))
        prune()
        save()
    }

    /// [from, to) 区间的周报统计：时长按天拆分；次数记在休息开始的当天
    func summary(from: Date, to: Date) -> WeeklySummary {
        let prevFrom = Calendar.current.date(byAdding: .day, value: -7, to: from) ?? from
        let cur = bucket(from: from, to: to)
        let prev = bucket(from: prevFrom, to: from)
        return WeeklySummary(
            start: from, end: to,
            days: cur.days,
            restSeconds: cur.restSeconds,
            manualCount: cur.manualCount,
            medCount: cur.medCount,
            prevRestSeconds: prev.restSeconds,
            prevManualCount: prev.manualCount,
            prevMedCount: prev.medCount)
    }

    private func bucket(from: Date, to: Date) -> (days: [DayStat], restSeconds: Double, manualCount: Int, medCount: Int) {
        let cal = Calendar.current
        var secondsByDay: [Date: Double] = [:]
        var manualByDay: [Date: Int] = [:]
        var medByDay: [Date: Int] = [:]
        var restSeconds: Double = 0
        var manualCount = 0
        var medCount = 0

        for record in records where record.end > from && record.start < to {
            let clippedStart = max(record.start, from)
            let clippedEnd = min(record.end, to)
            let day = cal.startOfDay(for: clippedStart)

            let seconds: Double
            switch record.kind {
            case .medication:
                seconds = Self.medicationCreditSeconds
                medCount += 1
                medByDay[day, default: 0] += 1
            case .manual:
                seconds = clippedEnd.timeIntervalSince(clippedStart)
                manualCount += 1
                manualByDay[day, default: 0] += 1
            case .screenOff:
                seconds = clippedEnd.timeIntervalSince(clippedStart)
            }
            guard seconds > 0 else { continue }
            restSeconds += seconds

            // 时长按天拆分（跨午夜的记录分摊）
            var cursor = clippedStart
            while cursor < clippedEnd {
                let nextDay = cal.startOfDay(for: (cal.date(byAdding: .day, value: 1, to: cursor) ?? clippedEnd))
                let sliceEnd = min(nextDay, clippedEnd)
                let slice = max(0, sliceEnd.timeIntervalSince(cursor))
                if slice > 0 {
                    secondsByDay[cal.startOfDay(for: cursor), default: 0] += slice
                }
                cursor = sliceEnd
            }
        }

        var days: [DayStat] = []
        var dayCursor = cal.startOfDay(for: from)
        while dayCursor < to {
            days.append(DayStat(day: dayCursor,
                                restSeconds: secondsByDay[dayCursor] ?? 0,
                                manualCount: manualByDay[dayCursor] ?? 0,
                                medCount: medByDay[dayCursor] ?? 0))
            dayCursor = cal.date(byAdding: .day, value: 1, to: dayCursor) ?? to
        }
        return (days, restSeconds, manualCount, medCount)
    }

    private func prune() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        records.removeAll { $0.end < cutoff }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([RestRecord].self, from: data) else { return }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
