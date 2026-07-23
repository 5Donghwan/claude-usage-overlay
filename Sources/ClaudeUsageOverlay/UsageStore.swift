import Foundation
import Combine

// MARK: - Geometry tunables (overridable at runtime via tunables.json)

struct Tunables: Decodable, Equatable {
    // Empirically calibrated (2026-07-23) against Claude.app's own composer
    // toolbar so the overlay sits at the same height/weight as the model name
    // and effort-level label next to it. Override any of these via
    // tunables.json without rebuilding.
    var barW: CGFloat = 86             // 기준 100에서 10%+ 축소
    var groupGap: CGFloat = 18
    var panelH: CGFloat = 30
    var sidePad: CGFloat = 4
    var scale: CGFloat = 1.0
    var centerAboveBottom: CGFloat = 19  // 입력창 컨테이너 하단 → 오버레이 중심

    // Named instances of the variable font extracted from Claude.app, so the
    // overlay text matches the app's own UI face (its composer toolbar labels
    // render at Text Regular / 12px). Falls back to the system font if
    // scripts/extract-fonts.mjs hasn't been run.
    var titleFont = "AnthropicSansVariable-TextRegular"
    var valueFont = "AnthropicSansVariable-TextRegular"
    var titleSize: CGFloat = 12
    var valueSize: CGFloat = 12

    var panelW: CGFloat { barW * 2 + groupGap + sidePad * 2 }

    private enum CodingKeys: String, CodingKey {
        case barW, groupGap, panelH, sidePad, scale, centerAboveBottom
        case titleFont, valueFont, titleSize, valueSize
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Tunables()
        barW = try c.decodeIfPresent(CGFloat.self, forKey: .barW) ?? d.barW
        groupGap = try c.decodeIfPresent(CGFloat.self, forKey: .groupGap) ?? d.groupGap
        panelH = try c.decodeIfPresent(CGFloat.self, forKey: .panelH) ?? d.panelH
        sidePad = try c.decodeIfPresent(CGFloat.self, forKey: .sidePad) ?? d.sidePad
        scale = try c.decodeIfPresent(CGFloat.self, forKey: .scale) ?? d.scale
        centerAboveBottom = try c.decodeIfPresent(CGFloat.self, forKey: .centerAboveBottom) ?? d.centerAboveBottom
        titleFont = try c.decodeIfPresent(String.self, forKey: .titleFont) ?? d.titleFont
        valueFont = try c.decodeIfPresent(String.self, forKey: .valueFont) ?? d.valueFont
        titleSize = try c.decodeIfPresent(CGFloat.self, forKey: .titleSize) ?? d.titleSize
        valueSize = try c.decodeIfPresent(CGFloat.self, forKey: .valueSize) ?? d.valueSize
    }
}

// MARK: - Usage data (written by the Claude desktop app itself, ~every 5 min)

final class UsageStore: ObservableObject {
    @Published private(set) var fiveHour: Double?
    @Published private(set) var sevenDay: Double?
    @Published private(set) var tun = Tunables()

    /// Samples older than this are treated as unknown ("--").
    private let staleAfter: TimeInterval = 90 * 60

    private let usagePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
    private let tunablesPath: URL
    private var timer: Timer?

    init(projectDir: URL) {
        tunablesPath = projectDir.appendingPathComponent("tunables.json")
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = 5
    }

    private struct History: Decodable {
        struct Sample: Decodable {
            struct U: Decodable {
                let fh: Double?
                let sd: Double?
            }
            let t: Double
            let u: U
        }
        let samples: [Sample]
    }

    func refresh() {
        var newFH: Double?
        var newSD: Double?
        if let data = try? Data(contentsOf: usagePath),
           let hist = try? JSONDecoder().decode(History.self, from: data),
           let latest = hist.samples.max(by: { $0.t < $1.t }) {
            let age = Date().timeIntervalSince1970 - latest.t / 1000
            if age < staleAfter {
                newFH = latest.u.fh
                newSD = latest.u.sd
            }
        }
        if newFH != fiveHour { fiveHour = newFH }
        if newSD != sevenDay { sevenDay = newSD }

        var newTun = Tunables()
        if let data = try? Data(contentsOf: tunablesPath),
           let t = try? JSONDecoder().decode(Tunables.self, from: data) {
            newTun = t
        }
        if newTun != tun {
            tun = newTun
            Log.write("tunables updated: barW=\(newTun.barW) centerAboveBottom=\(newTun.centerAboveBottom)")
        }
    }
}

// MARK: - Tiny file logger

enum Log {
    static let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/ClaudeUsageOverlay.log")

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ msg: String) {
        let line = "\(formatter.string(from: Date())) \(msg)\n"
        if let h = try? FileHandle(forWritingTo: path) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data(line.utf8))
        } else {
            try? line.write(to: path, atomically: true, encoding: .utf8)
        }
    }
}
