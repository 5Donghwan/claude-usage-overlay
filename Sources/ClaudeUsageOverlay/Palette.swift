import AppKit
import SwiftUI

// MARK: - Bar colors, taken from Claude's own design tokens
//
// These are the app's fill tokens — the ones it uses to paint filled elements,
// not the darker --success-100/--warning-100 text colors:
//
//   --cds-fill-success -> --cds-green-450  #009300
//   --cds-fill-warning -> --cds-yellow-200 #fab219
//   --cds-fill-danger  -> --cds-red-450    #d03b3b
//
// They resolve to fixed palette entries rather than per-theme values, so a
// single constant each is faithful in both light and dark mode.

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}

enum Palette {
    static let success = Color(hex: 0x009300)
    static let warning = Color(hex: 0xFAB219)
    static let danger = Color(hex: 0xD03B3B)

    /// Bar fill for a usage percentage.
    ///
    /// The defaults come from the server's own `severity` field in the /usage
    /// response, which called 76% "warning" while 39% and 49% were "normal" —
    /// putting the boundary in (49, 76]. Both are overridable via tunables.json.
    static func fill(for pct: Double, warnAt: Double, dangerAt: Double) -> Color {
        if pct >= dangerAt { return danger }
        if pct >= warnAt { return warning }
        return success
    }
}
