import Foundation

// MARK: - Per-model usage limits (e.g. "Fable" weekly)
//
// The desktop app polls GET /api/organizations/<org>/usage every ~4.5 min. That
// response carries a server-driven `limits[]` array which is the ONLY place the
// per-model figures live:
//
//   {"kind":"weekly_scoped","percent":49,
//    "scope":{"model":{"display_name":"Fable"}}, ...}
//
// Unlike five_hour/seven_day, these are NOT written to plan-usage-history.json —
// the app persists only its eight legacy named windows, and for this account all
// of the per-model ones come back null. So the response body cached by Chromium
// is the only on-disk copy.
//
// This reader is strictly best-effort: it only ever reads a cached RESPONSE BODY
// (never cookies or any credential), and every failure path returns nil so the
// 5h/7d bars — which come from the far more stable history file — keep working.

struct ModelLimit: Equatable {
    let name: String     // e.g. "Fable"
    let percent: Double
}

enum LimitsCache {
    private static let cacheDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/Cache/Cache_Data")

    // Chromium "simple cache" entry framing.
    private static let entryMagic = Data([0x30, 0x5c, 0x72, 0xa7, 0x1b, 0x6d, 0xfb, 0xfc])
    private static let eofMagic = Data([0xd8, 0x41, 0x0d, 0x97, 0x45, 0x6f, 0xfa, 0xf4])
    private static let zstdMagic = Data([0x28, 0xb5, 0x2f, 0xfd])

    /// Newest cached /usage response, if it is fresh enough to trust.
    static func modelLimits(staleAfter: TimeInterval) -> [ModelLimit]? {
        guard let (data, mtime) = newestUsageEntry() else { return nil }
        guard Date().timeIntervalSince(mtime) < staleAfter else { return nil }
        guard let json = decodeBody(data) else { return nil }
        return parseLimits(json)
    }

    // MARK: - Locating the entry

    private static func newestUsageEntry() -> (Data, Date)? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]) else { return nil }

        // Cache_Data holds thousands of files; only inspect the most recent few.
        let candidates = entries
            .filter { $0.lastPathComponent.hasSuffix("_0") && $0.lastPathComponent.count == 18 }
            .compactMap { url -> (URL, Date)? in
                guard let m = try? url.resourceValues(forKeys: keys).contentModificationDate
                else { return nil }
                return (url, m)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(60)

        for (url, mtime) in candidates {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  data.count > 32,
                  data.prefix(8) == entryMagic else { continue }

            let keyLen = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self) })
            let keyStart = 24
            guard keyLen > 0, keyLen < 4096, data.count > keyStart + keyLen else { continue }
            let key = String(decoding: data[keyStart..<(keyStart + keyLen)], as: UTF8.self)
            guard key.contains("/usage") else { continue }

            let bodyStart = keyStart + keyLen
            guard let eof = data.range(of: eofMagic, in: bodyStart..<data.count) else { continue }
            let body = data[bodyStart..<eof.lowerBound]
            guard !body.isEmpty else { continue }
            return (Data(body), mtime)
        }
        return nil
    }

    // MARK: - Decoding

    /// Bodies are zstd-compressed in practice. macOS has no zstd in its
    /// Compression framework and ships no libzstd, so shell out when a binary is
    /// available; otherwise give up quietly (the feature just stays hidden).
    private static func decodeBody(_ body: Data) -> Any? {
        if body.prefix(4) != zstdMagic {
            // Uncompressed (or an encoding we do not handle) — try as-is.
            return try? JSONSerialization.jsonObject(with: body)
        }
        guard let zstd = zstdBinary() else {
            Log.once("zstd binary not found; per-model limits unavailable")
            return nil
        }
        guard let raw = runZstd(zstd, input: body) else { return nil }
        return try? JSONSerialization.jsonObject(with: raw)
    }

    private static func zstdBinary() -> String? {
        for p in ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"]
        where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return nil
    }

    private static func runZstd(_ path: String, input: Data) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["-dc"]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr
        do {
            try p.run()
        } catch {
            return nil
        }
        // Write on a background queue so a full pipe buffer cannot deadlock us.
        DispatchQueue.global(qos: .utility).async {
            stdin.fileHandleForWriting.write(input)
            try? stdin.fileHandleForWriting.close()
        }
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        _ = stderr.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 && !out.isEmpty ? out : nil
    }

    // MARK: - Parsing

    /// Pull every model-scoped window out of `limits[]`, newest schema first.
    private static func parseLimits(_ json: Any) -> [ModelLimit] {
        guard let root = json as? [String: Any],
              let limits = root["limits"] as? [[String: Any]] else { return [] }
        var out: [ModelLimit] = []
        for l in limits {
            guard let scope = l["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any],
                  let name = model["display_name"] as? String,
                  !name.isEmpty,
                  let pct = l["percent"] as? Double else { continue }
            out.append(ModelLimit(name: name, percent: pct))
        }
        return out
    }
}
