import Foundation

struct MedTime: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var hour: Int
    var minute: Int

    var secondsOfDay: Int { hour * 3600 + minute * 60 }
    var label: String { String(format: "%02d:%02d", hour, minute) }

    static let standard: [MedTime] = [
        MedTime(hour: 11, minute: 0),
        MedTime(hour: 15, minute: 0),
        MedTime(hour: 20, minute: 0),
    ]

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
        self.id = UUID()
    }

    /// 从 UserDefaults 反序列化时保留 id
    init(id: UUID, hour: Int, minute: Int) {
        self.id = id
        self.hour = hour
        self.minute = minute
    }
}

/// 某时刻之后，下一个用药时间点（含跨天；严格晚于 date）
func nextOccurrence(after date: Date, times: [MedTime], calendar: Calendar = .current) -> Date? {
    times
        .flatMap { time -> [Date] in
            guard let today = calendar.date(bySettingHour: time.hour,
                                            minute: time.minute, second: 0, of: date) else { return [] }
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)
            return [today, tomorrow].compactMap { $0 }.filter { $0 > date }
        }
        .min()
}

func formatDuration(_ interval: TimeInterval) -> String {
    let total = max(0, Int(interval.rounded()))
    if total >= 3600 {
        let h = total / 3600, m = (total % 3600) / 60
        return m == 0 ? "\(h) 小时" : "\(h) 小时 \(m) 分"
    }
    if total >= 60 {
        let m = total / 60, s = total % 60
        return s == 0 ? "\(m) 分钟" : "\(m) 分 \(s) 秒"
    }
    return "\(total) 秒"
}

func clockString(_ date: Date?) -> String {
    guard let date else { return "--:--" }
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

/// 周报统计区间的终点：最近一个「周六 09:00」（可能晚于 now，此时调用方回退一周）
func lastReportEnd(from now: Date, calendar: Calendar = .current) -> Date {
    var candidate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
    while calendar.component(.weekday, from: candidate) != 7 {
        guard let prev = calendar.date(byAdding: .day, value: -1, to: candidate) else { break }
        candidate = prev
    }
    if candidate > now, let prevWeek = calendar.date(byAdding: .day, value: -7, to: candidate) {
        candidate = prevWeek
    }
    return candidate
}
