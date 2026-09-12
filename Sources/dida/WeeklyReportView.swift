import SwiftUI

/// 周报窗口：参考 Apple 屏幕使用时间的卡片式汇总
struct WeeklyReportView: View {
    let summary: WeeklySummary

    private var deltaText: String {
        guard summary.prevRestSeconds > 0 else { return "上周无数据" }
        let delta = (summary.restSeconds - summary.prevRestSeconds) / summary.prevRestSeconds
        let percent = Int(abs(delta) * 100)
        let arrow = delta >= 0 ? "↑" : "↓"
        return percent == 0 ? "与上周持平" : "\(arrow) \(percent)%"
    }

    private var prevHoursText: String {
        let total = Int(summary.prevRestSeconds) / 60
        if total >= 60 { return "\(total / 60) 小时 \(total % 60) 分" }
        return "\(total) 分钟"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("HY")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Dida.brand)
                Text("休息周报")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text(rangeText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // 主卡：总时长 + 环比
            VStack(alignment: .leading, spacing: 5) {
                Text("本周休息总时长")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(summary.restHoursText)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(Dida.brand)
                        .monospacedDigit()
                    Text(deltaText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(summary.restSeconds >= summary.prevRestSeconds ? Dida.blue : Dida.amber)
                }
                Text("含主动休息 + 熄屏 + 滴眼药水（每次计 1 分钟）")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Dida.indigo.opacity(0.14), Dida.violet.opacity(0.10)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            )

            // 统计 chips
            HStack(spacing: 8) {
                statChip("主动休息", "\(summary.manualCount) 次")
                statChip("滴眼药水", "\(summary.medCount) 次")
                statChip("日均", "\(avgMinutes) 分钟")
            }

            // 每日分布
            VStack(alignment: .leading, spacing: 6) {
                Text("每日分布")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(summary.days) { day in
                        dayBar(day)
                    }
                }
                .frame(height: 110)
            }

            Text("上周：休息 \(prevHoursText) · 主动 \(summary.prevManualCount) 次 · 滴药 \(summary.prevMedCount) 次")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("滴眼药水本身就是眼睛的休息。数字会随使用慢慢积累。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 380)
        .background(.ultraThinMaterial)
    }

    private var rangeText: String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return "\(f.string(from: summary.start)) – \(f.string(from: summary.end))"
    }

    private var avgMinutes: Int {
        Int(summary.restSeconds / 60 / 7)
    }

    private func statChip(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Dida.indigo)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private func dayBar(_ day: DayStat) -> some View {
        let maxSeconds = max(60, summary.days.map { $0.restSeconds }.max() ?? 60)
        let ratio = min(1, day.restSeconds / maxSeconds)
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return VStack(spacing: 4) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(day.restSeconds > 0 ? AnyShapeStyle(Dida.brand) : AnyShapeStyle(Color.primary.opacity(0.10)))
                .frame(height: max(6, CGFloat(ratio) * 78))
            Text(f.string(from: day.day))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
