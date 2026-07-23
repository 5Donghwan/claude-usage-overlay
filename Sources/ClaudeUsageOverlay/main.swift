import AppKit
import CoreText

if CommandLine.arguments.contains("--probe") {
    runProbe()
}

// The project dir doubles as the home of tunables.json and fonts/ (both
// live-editable without a rebuild). build.sh always produces
// <repo>/dist/ClaudeUsageOverlay.app, so the repo root is two levels up from
// the running bundle; CLAUDE_USAGE_OVERLAY_DIR overrides this for anyone who
// relocates the built .app away from the checkout.
func resolveProjectDir() -> URL {
    if let override = ProcessInfo.processInfo.environment["CLAUDE_USAGE_OVERLAY_DIR"] {
        return URL(fileURLWithPath: override)
    }
    return Bundle.main.bundleURL           // .../dist/ClaudeUsageOverlay.app
        .deletingLastPathComponent()       // .../dist
        .deletingLastPathComponent()       // repo root
}

let projectDir = resolveProjectDir()

/// Register the Anthropic Sans faces extracted from Claude.app (fonts/) so the
/// overlay text renders in the exact same face as the app's own UI.
func registerBundledFonts() {
    let dir = projectDir.appendingPathComponent("fonts")
    guard let files = try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: nil) else {
        Log.write("no fonts dir; using system font fallback")
        return
    }
    for f in files where ["ttf", "otf"].contains(f.pathExtension.lowercased()) {
        var err: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(f as CFURL, .process, &err) {
            Log.write("font registered: \(f.lastPathComponent)")
        } else {
            let msg = (err?.takeRetainedValue()).map(String.init(describing:)) ?? "?"
            Log.write("font register failed: \(f.lastPathComponent) — \(msg)")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = OverlayController(projectDir: projectDir)
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("launched (pid \(ProcessInfo.processInfo.processIdentifier))")
        registerBundledFonts()
        controller.start()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
