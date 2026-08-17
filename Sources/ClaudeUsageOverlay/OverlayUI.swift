import AppKit
import SwiftUI

// MARK: - SwiftUI content

struct BarGroup: View {
    let title: String
    let pct: Double?
    let tun: Tunables

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(title)
                    .font(.custom(tun.titleFont, size: tun.titleSize))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(pct.map { "\(Int($0.rounded()))%" } ?? "--")
                    .font(.custom(tun.valueFont, size: tun.valueSize).monospacedDigit())
                    .foregroundStyle(pct == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.14))
                if let pct {
                    GeometryReader { geo in
                        Capsule()
                            .fill(Palette.fill(for: pct, warnAt: tun.warnAt, dangerAt: tun.dangerAt))
                            .frame(width: geo.size.width * min(max(pct, 0), 100) / 100)
                    }
                }
            }
            .frame(height: 4.5)
        }
        .frame(width: tun.barW)
    }
}

struct OverlayView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        let t = store.tun
        HStack(spacing: t.groupGap) {
            BarGroup(title: "5h", pct: store.fiveHour, tun: t)
            BarGroup(title: "7d", pct: store.sevenDay, tun: t)
            // One extra bar per model-scoped weekly limit the API reports
            // (e.g. "Fable"), so new ones appear without a code change.
            ForEach(store.modelLimits, id: \.name) { limit in
                BarGroup(title: limit.name, pct: limit.percent, tun: t)
            }
        }
        .padding(.horizontal, t.sidePad)
        .scaleEffect(t.scale, anchor: .center)
        .frame(width: t.panelW(bars: store.barCount), height: t.panelH)
    }
}

// MARK: - Controller: panel lifecycle + position polling

final class OverlayController: NSObject {
    private let store: UsageStore
    private let tracker = ClaudeTracker()
    private var panel: NSPanel!
    private var pollTimer: Timer?
    private var lastOverlapScan = Date.distantPast
    private var cachedObstacles: [CGRect] = []
    private var overlapping = false

    init(projectDir: URL) {
        store = UsageStore(projectDir: projectDir)
        super.init()
    }

    func start() {
        makePanel()
        store.start()
        ensureAccessibilityThenRun()
    }

    private func makePanel() {
        let t = store.tun
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: t.panelW(bars: store.barCount), height: t.panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true          // never intercepts clicks meant for Claude
        p.hidesOnDeactivate = false          // visibility is managed by the poll loop
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: OverlayView(store: store))
        panel = p
    }

    private func ensureAccessibilityThenRun() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
            Log.write("accessibility already granted; tracking started")
            beginPolling()
            return
        }
        Log.write("waiting for accessibility grant")
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard AXIsProcessTrusted() else { return }
            t.invalidate()
            Log.write("accessibility granted; tracking started")
            self?.beginPolling()
        }
    }

    private func beginPolling() {
        let t = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = 0.03
        pollTimer = t
    }

    private func tick() {
        guard let claude = tracker.claudeApp(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == claude.processIdentifier,
              let placement = tracker.inputPlacement() else {
            hide()
            return
        }

        let t = store.tun
        let panelW = t.panelW(bars: store.barCount)
        let centerYAX = placement.anchorBottom - t.centerAboveBottom
        let topAX = centerYAX - t.panelH / 2
        let x = placement.inputFrame.midX - panelW / 2

        // The composer's layout differs per surface: on the chat surface the
        // model picker sits exactly where the code surface leaves a gap. Rather
        // than guess which surface is up, hide whenever a real control is in the
        // way — that also survives future layout changes.
        let panelAX = CGRect(x: x, y: topAX, width: panelW, height: t.panelH)
        if t.hideOnOverlap, isBlocked(panelAX, placement: placement, tun: t) {
            if !overlapping {
                overlapping = true
                Log.write("hidden: overlay would overlap composer controls")
            }
            hide()
            return
        }
        if overlapping {
            overlapping = false
            Log.write("shown: composer has room again")
        }

        // AX coords have a top-left origin on the primary display; AppKit a bottom-left one.
        guard let primary = NSScreen.screens.first else { return }
        let y = primary.frame.maxY - (topAX + t.panelH)

        let frame = NSRect(x: x, y: y, width: panelW, height: t.panelH)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    /// True when any toolbar control intrudes into the overlay's rect.
    private func isBlocked(_ panelAX: CGRect, placement: ClaudeTracker.Placement, tun: Tunables) -> Bool {
        guard let container = placement.container else { return false }
        // Walking the subtree is far too costly at the 10 Hz position rate.
        if Date().timeIntervalSince(lastOverlapScan) > 0.5 {
            lastOverlapScan = Date()
            let band = panelAX.minY...panelAX.maxY
            cachedObstacles = tracker.toolbarFrames(in: container, band: band)
        }
        let padded = panelAX.insetBy(dx: -tun.overlapMargin, dy: 0)
        return cachedObstacles.contains { $0.intersects(padded) }
    }

    private func hide() {
        if panel.isVisible {
            panel.orderOut(nil)
        }
    }
}
