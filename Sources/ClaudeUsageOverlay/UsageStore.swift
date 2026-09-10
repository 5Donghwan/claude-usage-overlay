import Foundation
import Combine

// MARK: - Geometry tunables (overridable at runtime via tunables.json)

struct Tunables: Decodable, Equatable {
    // Empirically calibrated against Claude.app's own composer toolbar so the
    // overlay sits at the same height/weight as the model name and
    // effort-level label next to it. Override any of these via tunables.json
    // without rebuilding.
    var barW: CGFloat = 86             // 기준 100에서 10%+ 축소
    var groupGap: CGFloat = 18
    var panelH: CGFloat = 30
    var sidePad: CGFloat = 4
    var scale: CGFloat = 1.0
    // 2026-09-10: positioning now anchors directly to the model/effort
    // AXPopUpButton row (ClaudeTracker.findToolbarRow), not to this offset —
    // see directAnchorOffset below. centerAboveBottom only fires as a
    // fallback on the rare tick where no toolbar control can be found at
    // all, so it no longer needs to be kept in precise sync with Claude's
    // layout; the value below is just the last real measurement, kept as a
    // reasonable fallback rather than an arbitrary number.
    var centerAboveBottom: CGFloat = 11.5  // 입력창 컨테이너 하단 → 오버레이 중심 (fallback 전용)

    // Primary anchor: added on top of the toolbar row's own measured center.
    // 0 means "exactly centered on the row", which is the intended default —
    // this exists purely as a manual fine-tune escape hatch.
    var directAnchorOffset: CGFloat = 0

    // Named instances of the variable font extracted from Claude.app, so the
    // overlay text matches the app's own UI face (its composer toolbar labels
    // render at Text Regular / 12px). Falls back to the system font if
    // scripts/extract-fonts.mjs hasn't been run.
    var titleFont = "AnthropicSansVariable-TextRegular"
    var valueFont = "AnthropicSansVariable-TextRegular"
    var titleSize: CGFloat = 12
    var valueSize: CGFloat = 12

    /// Show an extra bar per model-scoped weekly limit (e.g. "Fable"), when one
    /// is available. See LimitsCache for why this can silently stay hidden.
    var showModelLimits = true

    /// Usage percentages at which a bar turns yellow, then red. Defaults follow
    /// the server's own severity boundary — see Palette.fill(for:).
    var warnAt: Double = 75
    var dangerAt: Double = 90

    /// Hide instead of drawing on top of composer controls. The chat surface
    /// puts its model picker where the code surface leaves a gap, so without
    /// this the bars collide there.
    var hideOnOverlap = true
    var overlapMargin: CGFloat = 8

    func panelW(bars: Int) -> CGFloat {
        let n = max(1, bars)
        return barW * CGFloat(n) + groupGap * CGFloat(n - 1) + sidePad * 2
    }

    private enum CodingKeys: String, CodingKey {
        case barW, groupGap, panelH, sidePad, scale, centerAboveBottom, directAnchorOffset
        case titleFont, valueFont, titleSize, valueSize, showModelLimits
        case warnAt, dangerAt, hideOnOverlap, overlapMargin
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
        directAnchorOffset = try c.decodeIfPresent(CGFloat.self, forKey: .directAnchorOffset) ?? d.directAnchorOffset
        titleFont = try c.decodeIfPresent(String.self, forKey: .titleFont) ?? d.titleFont
        valueFont = try c.decodeIfPresent(String.self, forKey: .valueFont) ?? d.valueFont
        titleSize = try c.decodeIfPresent(CGFloat.self, forKey: .titleSize) ?? d.titleSize
        valueSize = try c.decodeIfPresent(CGFloat.self, forKey: .valueSize) ?? d.valueSize
        showModelLimits = try c.decodeIfPresent(Bool.self, forKey: .showModelLimits) ?? d.showModelLimits
        warnAt = try c.decodeIfPresent(Double.self, forKey: .warnAt) ?? d.warnAt
        dangerAt = try c.decodeIfPresent(Double.self, forKey: .dangerAt) ?? d.dangerAt
        hideOnOverlap = try c.decodeIfPresent(Bool.self, forKey: .hideOnOverlap) ?? d.hideOnOverlap
        overlapMargin = try c.decodeIfPresent(CGFloat.self, forKey: .overlapMargin) ?? d.overlapMargin
    }
}

// MARK: - Usage data (written by the Claude desktop app itself, ~every 5 min)

final class UsageStore: ObservableObject {
    @Published private(set) var fiveHour: Double?
    @Published private(set) var sevenDay: Double?
    @Published private(set) var modelLimits: [ModelLimit] = []
    @Published private(set) var tun = Tunables()

    /// Total bars currently rendered — drives the panel width.
    var barCount: Int { 2 + modelLimits.count }

    /// Samples older than this are treated as unknown ("--").
    private let staleAfter: TimeInterval = 90 * 60

    private let usagePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
    private let tunablesPath: URL
    private var timer: Timer?
    private var limitsTimer: Timer?

    init(projectDir: URL) {
        tunablesPath = projectDir.appendingPathComponent("tunables.json")
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = 5

        // Heavier than the history-file read (scans the HTTP cache and shells
        // out to zstd), and the app only refetches every ~4.5 min, so poll it
        // far less often and off the main thread.
        refreshModelLimits()
        limitsTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshModelLimits()
        }
        limitsTimer?.tolerance = 15
    }

    private func refreshModelLimits() {
        guard tun.showModelLimits else {
            if !modelLimits.isEmpty { modelLimits = [] }
            return
        }
        let cutoff = staleAfter
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = LimitsCache.modelLimits(staleAfter: cutoff) ?? []
            DispatchQueue.main.async {
                guard let self, self.modelLimits != found else { return }
                if !found.isEmpty {
                    let desc = found.map { "\($0.name)=\(Int($0.percent))%" }.joined(separator: " ")
                    Log.once("model limits: \(desc)")
                }
                self.modelLimits = found
            }
        }
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

    private static var seen = Set<String>()
    private static let seenLock = NSLock()

    /// Log a message only the first time it appears — for state polled on a
    /// timer, where repeating the same line every minute would bury the log.
    static func once(_ msg: String) {
        seenLock.lock()
        let isNew = seen.insert(msg).inserted
        seenLock.unlock()
        if isNew { write(msg) }
    }
}
