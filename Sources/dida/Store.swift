import Foundation
import Combine

/// 全部用户设置，持久化到 UserDefaults。
@MainActor
final class Store: ObservableObject {
    private let d: UserDefaults

    @Published var medTimes: [MedTime] { didSet { saveTimes() } }
    @Published var med1Name: String { didSet { d.set(med1Name, forKey: "med1Name") } }
    @Published var med2Name: String { didSet { d.set(med2Name, forKey: "med2Name") } }
    @Published var gapMinutes: Int { didSet { d.set(gapMinutes, forKey: "gapMinutes") } }
    @Published var workIntervalMinutes: Int { didSet { d.set(workIntervalMinutes, forKey: "workIntervalMinutes") } }
    @Published var restMinutes: Int { didSet { d.set(restMinutes, forKey: "restMinutes") } }
    @Published var muteMinutes: Int { didSet { d.set(muteMinutes, forKey: "muteMinutes") } }
    @Published var launchAtLogin: Bool { didSet { LoginItem.set(launchAtLogin) } }
    @Published var playSound: Bool { didSet { d.set(playSound, forKey: "playSound") } }

    init(defaults: UserDefaults = .standard) {
        d = defaults
        d.register(defaults: [
            "med1Name": "富马",
            "med2Name": "聚乙二醇",
            "gapMinutes": 5,
            "workIntervalMinutes": 20,
            "restMinutes": 5,
            "muteMinutes": 60,
            "playSound": true,
        ])

        if let data = d.data(forKey: "medTimesData"),
           let decoded = try? JSONDecoder().decode([MedTime].self, from: data), !decoded.isEmpty {
            medTimes = decoded
        } else {
            medTimes = MedTime.standard
        }
        med1Name = d.string(forKey: "med1Name") ?? "富马"
        med2Name = d.string(forKey: "med2Name") ?? "聚乙二醇"
        gapMinutes = max(1, d.integer(forKey: "gapMinutes"))
        workIntervalMinutes = min(60, max(5, d.integer(forKey: "workIntervalMinutes")))
        restMinutes = min(30, max(1, d.integer(forKey: "restMinutes")))
        muteMinutes = min(240, max(5, d.integer(forKey: "muteMinutes")))
        playSound = d.object(forKey: "playSound") == nil ? true : d.bool(forKey: "playSound")
        launchAtLogin = LoginItem.isEnabled()
    }

    private func saveTimes() {
        if let data = try? JSONEncoder().encode(medTimes) {
            d.set(data, forKey: "medTimesData")
        }
    }
}

/// 登录自启动：LaunchAgent 方式（未签名 bundle 用不了 SMAppService）。
enum LoginItem {
    static let label = "com.blueDaydreaming725.dida"

    static var available: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    static var plistPath: String {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
            .path
    }

    static var appPath: String { Bundle.main.bundlePath }

    static func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }

    static func set(_ on: Bool) {
        guard available else { return }
        if on {
            let exec = appPath + "/Contents/MacOS/dida"
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [exec],
                "RunAtLoad": true,
                "KeepAlive": false,
            ]
            let url = URL(fileURLWithPath: plistPath)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0) {
                try? data.write(to: url)
            }
            run(["/bin/launchctl", "load", plistPath])
        } else {
            run(["/bin/launchctl", "unload", plistPath])
            try? FileManager.default.removeItem(atPath: plistPath)
        }
    }

    private static func run(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        try? p.run()
    }
}
