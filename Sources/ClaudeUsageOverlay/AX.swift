import AppKit
import ApplicationServices

// MARK: - Low-level AX helpers

func axString(_ el: AXUIElement, _ attr: String) -> String? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
    return v as? String
}

func axElement(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success,
          let ref = v, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
    return (ref as! AXUIElement)
}

func axElements(_ el: AXUIElement, _ attr: String) -> [AXUIElement] {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success,
          let arr = v as? [AnyObject] else { return [] }
    return arr.compactMap {
        CFGetTypeID($0 as CFTypeRef) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil
    }
}

/// Frame in global screen coordinates with a TOP-LEFT origin (AX convention).
func axFrame(_ el: AXUIElement) -> CGRect? {
    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
          AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
          let pr = posRef, CFGetTypeID(pr) == AXValueGetTypeID(),
          let sr = sizeRef, CFGetTypeID(sr) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero
    var s = CGSize.zero
    guard AXValueGetValue((pr as! AXValue), .cgPoint, &p),
          AXValueGetValue((sr as! AXValue), .cgSize, &s) else { return nil }
    return CGRect(origin: p, size: s)
}

// MARK: - Claude window tracking

let claudeBundleID = "com.anthropic.claudefordesktop"

final class ClaudeTracker {
    private var pid: pid_t = -1
    private var appEl: AXUIElement?
    private var inputEl: AXUIElement?
    private var lastSearch = Date.distantPast
    private var loggedFind = false

    struct Placement {
        let inputFrame: CGRect     // AX coords (top-left origin)
        let anchorBottom: CGFloat  // bottom edge of the input container, AX coords
    }

    func claudeApp() -> NSRunningApplication? {
        if pid > 0, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated {
            return app
        }
        let found = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == claudeBundleID
        }
        if let f = found {
            pid = f.processIdentifier
            let el = AXUIElementCreateApplication(pid)
            // Electron only builds its accessibility tree when a client asks for it.
            AXUIElementSetAttributeValue(el, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            appEl = el
            inputEl = nil
            loggedFind = false
        } else {
            pid = -1
            appEl = nil
            inputEl = nil
        }
        return found
    }

    func inputPlacement() -> Placement? {
        guard let appEl else { return nil }
        guard let win = axElement(appEl, kAXFocusedWindowAttribute)
                ?? axElement(appEl, kAXMainWindowAttribute) else {
            inputEl = nil
            return nil
        }

        // Fast path: cached element still alive — just re-read its frame.
        if let el = inputEl, let f = axFrame(el), f.width >= 200 {
            return Placement(inputFrame: f, anchorBottom: containerBottom(for: el, inputFrame: f))
        }
        inputEl = nil

        // Re-search is comparatively expensive; rate-limit it.
        guard Date().timeIntervalSince(lastSearch) > 1.5 else { return nil }
        lastSearch = Date()
        // Re-assert in case the app was relaunched or dropped the tree.
        AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        guard let (el, f) = Self.findInputArea(in: win) else { return nil }
        inputEl = el
        if !loggedFind {
            Log.write("input area found at \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))")
            loggedFind = true
        }
        return Placement(inputFrame: f, anchorBottom: containerBottom(for: el, inputFrame: f))
    }

    /// BFS for the chat input: a wide text area in the lower part of the window.
    static func findInputArea(in window: AXUIElement) -> (AXUIElement, CGRect)? {
        guard let wf = axFrame(window) else { return nil }
        var queue: [AXUIElement] = [window]
        var index = 0
        var best: (el: AXUIElement, frame: CGRect)?
        while index < queue.count && queue.count < 6000 {
            let el = queue[index]
            index += 1
            if let role = axString(el, kAXRoleAttribute),
               role == "AXTextArea" || role == "AXTextField",
               let f = axFrame(el),
               f.width >= 250,
               f.midY > wf.midY,
               f.maxY <= wf.maxY + 2 {
                if best == nil
                    || f.maxY > best!.frame.maxY + 1
                    || (abs(f.maxY - best!.frame.maxY) <= 1 && f.width > best!.frame.width) {
                    best = (el, f)
                }
            }
            queue.append(contentsOf: axElements(el, kAXChildrenAttribute))
        }
        return best.map { ($0.el, $0.frame) }
    }

    /// The visual "input box" extends below the text area (toolbar row with
    /// model picker etc.). Find the ancestor group that adds that row; fall
    /// back to a fixed toolbar-height estimate.
    func containerBottom(for input: AXUIElement, inputFrame f: CGRect) -> CGFloat {
        var el = input
        for _ in 0..<8 {
            guard let parent = axElement(el, kAXParentAttribute) else { break }
            if let pf = axFrame(parent) {
                let extend = pf.maxY - f.maxY
                if extend > 110 || pf.width > f.width + 200 { break }
                if extend >= 14 && pf.width < f.width * 1.5 {
                    return pf.maxY
                }
            }
            el = parent
        }
        return f.maxY + 48
    }
}

// MARK: - Probe mode (--probe): dump the AX tree so heuristics can be verified

func runProbe() -> Never {
    guard AXIsProcessTrusted() else {
        print("NOT TRUSTED: grant Accessibility permission first")
        exit(2)
    }
    guard let claude = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == claudeBundleID
    }) else {
        print("Claude desktop app is not running")
        exit(3)
    }
    let appEl = AXUIElementCreateApplication(claude.processIdentifier)
    AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    Thread.sleep(forTimeInterval: 1.5) // give Electron a moment to build the tree

    guard let win = axElement(appEl, kAXFocusedWindowAttribute)
            ?? axElement(appEl, kAXMainWindowAttribute)
            ?? axElements(appEl, kAXWindowsAttribute).first else {
        print("no window")
        exit(4)
    }
    print("window frame: \(axFrame(win).map(String.init(describing:)) ?? "?")")

    var lines = 0
    func dump(_ el: AXUIElement, depth: Int) {
        guard lines < 2500, depth < 30 else { return }
        let role = axString(el, kAXRoleAttribute) ?? "?"
        let interesting = role == "AXTextArea" || role == "AXTextField"
            || role == "AXButton" || role == "AXGroup" || role == "AXWebArea"
            || role == "AXPopUpButton" || role == "AXComboBox"
        if interesting, let f = axFrame(el) {
            let pad = String(repeating: " ", count: min(depth, 40))
            let title = axString(el, kAXTitleAttribute) ?? axString(el, "AXPlaceholderValue") ?? ""
            print("\(pad)\(role) [\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))] \(title.prefix(40))")
            lines += 1
        }
        for child in axElements(el, kAXChildrenAttribute) {
            dump(child, depth: depth + 1)
        }
    }
    dump(win, depth: 0)

    if let (el, f) = ClaudeTracker.findInputArea(in: win) {
        print("\nCHOSEN input area: \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))")
        let tracker = ClaudeTracker()
        let bottom = tracker.containerBottom(for: el, inputFrame: f)
        print("container bottom: \(Int(bottom)) (input bottom \(Int(f.maxY)), delta \(Int(bottom - f.maxY)))")
    } else {
        print("\nNO input area matched the heuristic")
    }
    exit(0)
}
