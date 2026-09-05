import SwiftUI
import AppKit

// MARK: - 配色「蓝紫粉渐变」：重磅字母品牌色，蓝 = 富马/休息，紫 = 聚乙二醇，粉收尾
enum Dida {
    /// 行动蓝（滴药第 1 步 / 提醒中）
    static let indigo = Color(red: 0.35, green: 0.44, blue: 0.98)
    /// 紫（滴药第 2 步）
    static let violet = Color(red: 0.66, green: 0.33, blue: 0.96)
    /// 休息蓝
    static let blue = Color(red: 0.25, green: 0.60, blue: 0.98)
    /// 静音琥珀
    static let amber = Color(red: 0.95, green: 0.62, blue: 0.10)
    /// 品牌粉（渐变收尾）
    static let pink = Color(red: 0.93, green: 0.28, blue: 0.60)
    /// 品牌渐变：蓝 → 紫 → 粉
    static let brand = LinearGradient(colors: [Color(red: 0.23, green: 0.51, blue: 0.96), violet, pink],
                                      startPoint: .leading, endPoint: .trailing)
    /// 主行动渐变
    static let action = LinearGradient(colors: [Color(red: 0.23, green: 0.51, blue: 0.96), violet],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
    /// 玻璃 1px 描边
    static let hairline = Color.primary.opacity(0.10)
}

extension Color {
    var nsColor: NSColor {
        let c = components()
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.opacity)
    }

    private func components() -> (red: CGFloat, green: CGFloat, blue: CGFloat, opacity: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}

// MARK: - 渐变主按钮

struct GradientProminentStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, compact ? 5 : 9)
            .padding(.horizontal, compact ? 10 : 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: compact ? 7 : 10, style: .continuous)
                    .fill(Dida.action)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 真·毛玻璃（NSVisualEffectView，behindWindow 实时模糊桌面内容）

struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var radius: CGFloat = 16

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = radius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - 脉冲环（用药提醒的注意力动效）

struct PulseRing: View {
    let tint: Color
    let delay: Double
    @State private var on = false

    var body: some View {
        Circle()
            .stroke(tint.opacity(on ? 0 : 0.5), lineWidth: 2)
            .scaleEffect(on ? 2.3 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(delay)) {
                    on = true
                }
            }
    }
}

// MARK: - 入场震动

@MainActor
enum Shake {
    /// 按给定振幅序列播放横向震动；amplitudes 最后必须是 0
    static func run(pattern: [CGFloat], durationPerStep: TimeInterval, apply: @escaping (CGFloat) -> Void) {
        for (index, offset) in pattern.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * durationPerStep) {
                withAnimation(.easeOut(duration: durationPerStep)) { apply(offset) }
            }
        }
    }
}

// MARK: - 用药强制确认弹窗

struct MedPopupView: View {
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String
    let onTaken: () -> Void
    let onSnooze: () -> Void

    @State private var appeared = false
    @State private var shakeX: CGFloat = 0

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    PulseRing(tint: iconTint, delay: 0)
                    PulseRing(tint: iconTint, delay: 0.8)
                    Circle()
                        .fill(
                            LinearGradient(colors: [iconTint.opacity(0.22), iconTint.opacity(0.10)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 54, height: 54)
                    Image(systemName: icon)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(iconTint)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button(action: onSnooze) {
                    Text("稍后 5 分钟")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(action: onTaken) {
                    Label("已滴完", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GradientProminentStyle())
            }
        }
        .padding(20)
        .frame(width: 410)
        .background(
            ZStack {
                GlassBackground(material: .hudWindow, radius: 18)
                LinearGradient(colors: [Dida.indigo.opacity(0.10), Dida.violet.opacity(0.08)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Dida.hairline, lineWidth: 1)
        )
        .shadow(color: Dida.violet.opacity(0.25), radius: 24, x: 0, y: 12)
        .scaleEffect(appeared ? 1 : 0.80)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -14)
        .offset(x: shakeX)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.60)) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                Shake.run(pattern: [14, -11, 8, -5, 3, -1, 0],
                          durationPerStep: 0.05) { shakeX = $0 }
            }
        }
    }
}

// MARK: - 轻量横幅（弹簧入场 + 震动 + 实时剩余秒数 + 进度）

struct BannerView: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let seconds: Int
    let onClose: () -> Void

    @State private var startedAt = Date()
    @State private var appeared = false
    @State private var shakeX: CGFloat = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = max(0, Double(seconds) - context.date.timeIntervalSince(startedAt))
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(colors: [tint.opacity(0.24), tint.opacity(0.10)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 32, height: 32)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text("\(Int(remaining.rounded(.up)))s")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(
                                LinearGradient(colors: [Dida.indigo.opacity(0.75), tint.opacity(0.75)],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: proxy.size.width * CGFloat(remaining / Double(seconds)))
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .frame(width: 350)
            .background(
                ZStack {
                    GlassBackground(material: .hudWindow, radius: 14)
                    LinearGradient(colors: [tint.opacity(0.06), Dida.violet.opacity(0.04)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Dida.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture(perform: onClose)
            .scaleEffect(appeared ? 1 : 0.86)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : -10)
            .offset(x: shakeX)
            .onAppear {
                withAnimation(.spring(response: 0.40, dampingFraction: 0.70)) { appeared = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
                    Shake.run(pattern: [7, -5, 3, -2, 0],
                              durationPerStep: 0.05) { shakeX = $0 }
                }
            }
        }
    }
}

// MARK: - 菜单栏面板

struct RootPopoverView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var state: AppState
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            medCard
            breakRow
            actions
            settings
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 330)
        .background(.ultraThinMaterial)
        .onChange(of: store.medTimes) { _ in state.medTimesChanged() }
        .onChange(of: store.workIntervalMinutes) { _ in state.workIntervalChanged() }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 8) {
            Text("HW")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Dida.brand)
            Text("滴答")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        let (text, color): (String, Color) = {
            if state.suspendKind == .rest { return ("休息中", Dida.blue) }
            if state.suspendKind == .mute { return ("已静音", Dida.amber) }
            return ("提醒中", Dida.indigo)
        }()
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.secondary)
    }

    // MARK: 用药倒计时卡片（蓝紫着色玻璃 + 大号圆体数字）

    private var medCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let nextLabel = state.medStep == .first ? store.med1Name : store.med2Name
            let stepText = state.medStep == .first ? "第 1/2 步" : "第 2/2 步"
            return VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("下次用药 · \(nextLabel)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Text(stepText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Dida.indigo)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Dida.indigo.opacity(0.12)))
                }
                Text(countdownMed(now: context.date))
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                    .foregroundStyle(Dida.brand)
                    .monospacedDigit()
                Text(subMed)
                    .font(.system(size: 12))
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
        }
    }

    private var subMed: String {
        if state.isSuspended { return "提醒暂停中" }
        return "先滴\(store.med1Name) → \(store.gapMinutes) 分钟后滴\(store.med2Name)"
    }

    private func countdownMed(now: Date) -> String {
        if state.suspendKind == .rest, let until = state.suspendedUntil {
            return "休息中 · \(formatDuration(until.timeIntervalSince(now)))后回来"
        }
        if state.isSuspended, let until = state.suspendedUntil {
            return "\(formatDuration(until.timeIntervalSince(now)))后恢复"
        }
        guard let target = state.nextMed else { return "--:--" }
        let remaining = target.timeIntervalSince(now)
        if remaining <= 0 { return "马上提醒" }
        return "\(clockString(target)) · \(formatDuration(remaining))后"
    }

    // MARK: 护眼休息行

    private var breakRow: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 8) {
                Image(systemName: "leaf")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Dida.blue)
                Text("护眼休息")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(countdownBreak(now: context.date))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Dida.blue)
                    .monospacedDigit()
            }
        }
    }

    private func countdownBreak(now: Date) -> String {
        if state.isSuspended { return "已暂停" }
        guard let target = state.nextBreak else { return "--" }
        let remaining = target.timeIntervalSince(now)
        if remaining <= 0 { return "马上" }
        return formatDuration(remaining) + "后"
    }

    // MARK: 操作

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: { state.medNow() }) {
                    Label("现在滴药", systemImage: "eyedropper")
                }
                .buttonStyle(GradientProminentStyle(compact: true))

                Button(action: { state.toggleRest() }) {
                    Text(state.suspendKind == .rest ? "休息回来" : "休息一下")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: { state.toggleMute() }) {
                    Text(state.suspendKind == .mute ? "恢复提醒" : "静音")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if state.suspendKind == .rest {
                Button(action: { state.extendRest() }) {
                    Label("再休 5 分钟 · 闭眼眨眼也有效", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Dida.blue)
                .controlSize(.small)
            }
        }
    }

    // MARK: 设置

    private var settings: some View {
        DisclosureGroup(isExpanded: $showSettings) {
            VStack(alignment: .leading, spacing: 12) {
                timesEditor
                gapsAndNames
                intervals
                TogglesRow(store: store)
            }
            .padding(.top, 10)
        } label: {
            Text("设置")
                .font(.system(size: 13, weight: .semibold))
        }
        .font(.system(size: 12))
    }

    private var timesEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("用药时间")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation { store.medTimes.append(MedTime(hour: 12, minute: 0)) }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Dida.indigo)
                .disabled(store.medTimes.count >= 6)
            }
            ForEach($store.medTimes) { $time in
                HStack {
                    DatePicker("", selection: Binding(
                        get: {
                            Calendar.current.date(bySettingHour: time.hour,
                                                  minute: time.minute, second: 0,
                                                  of: Date()) ?? Date()
                        },
                        set: { date in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                            time = MedTime(id: time.id,
                                           hour: comps.hour ?? 0,
                                           minute: comps.minute ?? 0)
                        }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .fixedSize()

                    Spacer()

                    Button {
                        withAnimation { store.medTimes.removeAll { $0.id == time.id } }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(store.medTimes.count <= 1)
                }
            }
        }
    }

    private var gapsAndNames: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("两药间隔")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper("\(store.gapMinutes) 分钟", value: $store.gapMinutes, in: 1...30)
                    .font(.system(size: 12))
            }
            HStack(spacing: 8) {
                Text("药名")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("先滴", text: $store.med1Name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                TextField("后滴", text: $store.med2Name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }
        }
    }

    private var intervals: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("护眼提醒")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper("每 \(store.workIntervalMinutes) 分钟",
                        value: $store.workIntervalMinutes, in: 5...60, step: 5)
                    .font(.system(size: 12))
            }
            HStack {
                Text("休息时长")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper("\(store.restMinutes) 分钟", value: $store.restMinutes, in: 1...30)
                    .font(.system(size: 12))
            }
            HStack {
                Text("静音时长")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper("\(store.muteMinutes) 分钟", value: $store.muteMinutes, in: 5...240, step: 5)
                    .font(.system(size: 12))
            }
        }
    }

    // MARK: 底部

    private var footer: some View {
        HStack {
            Text("⌥⌘B 休息 · ⌥⌘M 静音")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("退出滴答") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

private struct TogglesRow: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("用药提醒音效", isOn: $store.playSound)
                .font(.system(size: 12))
            if LoginItem.available {
                Toggle("登录时启动", isOn: $store.launchAtLogin)
                    .font(.system(size: 12))
            }
        }
    }
}
