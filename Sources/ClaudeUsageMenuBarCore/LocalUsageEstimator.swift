import Foundation

public struct LocalUsageEstimate: Sendable {
    public let dailyTokens: Int
    public let weeklyTokens: Int
    public let lifetimeInputTokens: Int
    public let lifetimeOutputTokens: Int
    public let sourceDescription: String

    public init(
        dailyTokens: Int,
        weeklyTokens: Int,
        lifetimeInputTokens: Int,
        lifetimeOutputTokens: Int,
        sourceDescription: String
    ) {
        self.dailyTokens = dailyTokens
        self.weeklyTokens = weeklyTokens
        self.lifetimeInputTokens = lifetimeInputTokens
        self.lifetimeOutputTokens = lifetimeOutputTokens
        self.sourceDescription = sourceDescription
    }

    public var lifetimeTotalTokens: Int {
        lifetimeInputTokens + lifetimeOutputTokens
    }
}

public enum LocalUsageEstimatorError: LocalizedError {
    case missingStatsCache
    case invalidStatsCache

    public var errorDescription: String? {
        switch self {
        case .missingStatsCache:
            return "Could not find ~/.claude/stats-cache.json. Run Claude Code at least once and try again."
        case .invalidStatsCache:
            return "Failed to parse ~/.claude/stats-cache.json."
        }
    }
}

public struct LocalUsageEstimator: Sendable {
    public init() {}

    public func estimate(now: Date = .now) throws -> LocalUsageEstimate {
        let path = NSHomeDirectory() + "/.claude/stats-cache.json"
        guard FileManager.default.fileExists(atPath: path) else {
            throw LocalUsageEstimatorError.missingStatsCache
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw LocalUsageEstimatorError.invalidStatsCache
        }

        let decoder = JSONDecoder()
        guard let cache = try? decoder.decode(StatsCache.self, from: data) else {
            throw LocalUsageEstimatorError.invalidStatsCache
        }

        // Primary source: per-message usage from Claude Code local logs.
        // This captures rolling windows and includes cache read/creation tokens that are often
        // material for "you've hit your limit" situations.
        let scanned = scanProjectsJSONL(now: now)
        var daily = scanned.daily
        var weekly = scanned.weekly
        var sourceDetails = scanned.sourceDetails

        // Fallback: stats-cache rollups (calendar-day based; may lag and isn't rolling-5h).
        if daily == 0 && weekly == 0 {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            let fromStats = computeFromStatsCache(cache: cache, calendar: calendar, today: today)
            daily = fromStats.daily
            weekly = fromStats.weekly
            sourceDetails = "~/.claude/stats-cache.json (fallback)"
        }

        var lifetimeIn = 0
        var lifetimeOut = 0
        if let usage = cache.modelUsage {
            for (_, v) in usage {
                lifetimeIn += v.inputTokens ?? 0
                lifetimeOut += v.outputTokens ?? 0
            }
        }

        let computed = cache.lastComputedDate ?? "unknown"
        let src = "\(sourceDetails) (stats-cache.lastComputedDate=\(computed))"

        return LocalUsageEstimate(
            dailyTokens: daily,
            weeklyTokens: weekly,
            lifetimeInputTokens: lifetimeIn,
            lifetimeOutputTokens: lifetimeOut,
            sourceDescription: src
        )
    }
}

private struct StatsCacheRollup {
    let daily: Int
    let weekly: Int
    let hasTodayEntry: Bool
}

private func computeFromStatsCache(cache: StatsCache, calendar: Calendar, today: Date) -> StatsCacheRollup {
    var daily = 0
    var weekly = 0
    var hasToday = false

    let dailyEntries = cache.dailyModelTokens ?? []
    for entry in dailyEntries {
        guard let day = entry.dateAsDate(in: calendar) else { continue }
        let dayStart = calendar.startOfDay(for: day)

        let tokens = entry.tokensByModel.values.reduce(0, +)

        if calendar.isDate(dayStart, inSameDayAs: today) {
            daily += tokens
            hasToday = true
        }

        if let diff = calendar.dateComponents([.day], from: dayStart, to: today).day,
           diff >= 0, diff < 7 {
            weekly += tokens
        }
    }

    return StatsCacheRollup(daily: daily, weekly: weekly, hasTodayEntry: hasToday)
}

private struct ProjectScanRollup {
    let daily: Int
    let weekly: Int
    let sourceDetails: String
}

private func scanProjectsJSONL(now: Date) -> ProjectScanRollup {
    let projectsRoot = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/projects", isDirectory: true)
    let fm = FileManager.default

    // Rolling windows:
    // - "daily": last 5 hours
    // - "weekly": last 7 days
    let windowEnd = now
    let fiveHourStart = now.addingTimeInterval(-5 * 60 * 60)
    let sevenDayStart = now.addingTimeInterval(-7 * 24 * 60 * 60)

    var dailyMaxByMessageID: [String: Double] = [:]
    var weeklyMaxByMessageID: [String: Double] = [:]

    var candidateFiles = 0
    var scannedFiles = 0
    var scannedLines = 0
    var usedFallback = false

    let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
    guard let enumerator = fm.enumerator(at: projectsRoot, includingPropertiesForKeys: keys) else {
        return ProjectScanRollup(daily: 0, weekly: 0, sourceDetails: "~/.claude/projects (unavailable)")
    }

    // Gather candidates then scan most-recent files first.
    // This keeps polling fast even if ~/.claude/projects grows large.
    var candidates: [(mtime: Date, url: URL)] = []
    candidates.reserveCapacity(512)

    for case let url as URL in enumerator {
        guard url.pathExtension == "jsonl" else { continue }
        guard let values = try? url.resourceValues(forKeys: Set(keys)),
              values.isRegularFile == true else { continue }

        // Optimization: skip very old files (keeps polling cheap).
        if let mtime = values.contentModificationDate,
           now.timeIntervalSince(mtime) > 60 * 60 * 24 * 30 {
            continue
        }

        if let mtime = values.contentModificationDate {
            candidateFiles += 1
            candidates.append((mtime: mtime, url: url))
        }
    }

    candidates.sort { $0.mtime > $1.mtime }

    // Hard cap: scan at most N files per refresh to avoid UI starvation.
    let maxFilesToScan = 200
    for entry in candidates.prefix(maxFilesToScan) {
        scannedFiles += 1
        let (d, w, lineCount, didUse) = scanOneJSONL(
            url: entry.url,
            window5hStart: fiveHourStart,
            window7dStart: sevenDayStart,
            windowEnd: windowEnd
        )
        scannedLines += lineCount
        usedFallback = usedFallback || didUse

        for (id, total) in d {
            if (dailyMaxByMessageID[id] ?? 0.0) < total { dailyMaxByMessageID[id] = total }
        }
        for (id, total) in w {
            if (weeklyMaxByMessageID[id] ?? 0.0) < total { weeklyMaxByMessageID[id] = total }
        }
    }

    let daily = Int(dailyMaxByMessageID.values.reduce(0.0, +).rounded())
    let weekly = Int(weeklyMaxByMessageID.values.reduce(0.0, +).rounded())

    let suffix = usedFallback ? ", dedupe=max-by-message-id" : ""
    let detail = "~/.claude/projects/**/*.jsonl (candidates=\(candidateFiles), scanned=\(scannedFiles), lines=\(scannedLines)\(suffix))"
    return ProjectScanRollup(daily: daily, weekly: weekly, sourceDetails: detail)
}

private func scanOneJSONL(
    url: URL,
    window5hStart: Date,
    window7dStart: Date,
    windowEnd: Date
) -> (daily: [String: Double], weekly: [String: Double], lineCount: Int, didUse: Bool) {
    guard let data = try? Data(contentsOf: url),
          let text = String(data: data, encoding: .utf8) else {
        return ([:], [:], 0, false)
    }

    var daily: [String: Double] = [:]
    var weekly: [String: Double] = [:]
    var lines = 0
    var didUse = false

    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
        lines += 1
        guard let lineData = rawLine.data(using: .utf8) else { continue }
        guard let any = try? JSONSerialization.jsonObject(with: lineData) else { continue }

        // Use outer timestamp if present; it's more consistent for filtering.
        let ts = extractISODate(from: any, key: "timestamp") ?? extractISODateDeep(from: any) // fallback
        guard let ts else { continue }

        if ts < window7dStart || ts >= windowEnd { continue }

        guard let record = extractMessageUsage(any: any) else { continue }
        didUse = true

        if ts >= window5hStart && ts < windowEnd {
            let total = max(0.0, record.weightedTotal(weights: dailyWeights))
            if (daily[record.id] ?? 0) < total { daily[record.id] = total }
        }
        if ts >= window7dStart && ts < windowEnd {
            let total = max(0.0, record.weightedTotal(weights: weeklyWeights))
            if (weekly[record.id] ?? 0) < total { weekly[record.id] = total }
        }
    }

    return (daily, weekly, lines, didUse)
}

private struct MessageUsageRecord {
    let id: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int
    let cacheReadInputTokens: Int

    func weightedTotal(weights: TokenWeights) -> Double {
        let io = inputTokens + outputTokens
        let weightedCacheCreate = Double(cacheCreationInputTokens) * weights.cacheCreationWeight
        let weightedCacheRead = Double(cacheReadInputTokens) * weights.cacheReadWeight
        return Double(io) + weightedCacheCreate + weightedCacheRead
    }
}

private func extractMessageUsage(any: Any) -> MessageUsageRecord? {
    // Common Claude Code schema:
    // { ..., "message": { "id": "...", "usage": { ... token fields ... } }, ... }
    if let dict = any as? [String: Any],
       let msg = dict["message"] as? [String: Any],
       let usage = msg["usage"] as? [String: Any] {
       let id = (msg["id"] as? String)
            ?? (dict["messageId"] as? String)
            ?? (dict["message_id"] as? String)
            ?? (dict["uuid"] as? String)
        if let id, let record = usageRecord(from: usage, id: id) {
            return record
        }
    }

    // Fallback: walk dictionaries to find a nested object with keys: id-ish + usage{...}
    var stack: [Any] = [any]
    var seen = 0

    while let cur = stack.popLast() {
        seen += 1
        if seen > 4000 { break } // safety guard

        if let dict = cur as? [String: Any] {
            if let usage = dict["usage"] as? [String: Any] {
                let id = (dict["id"] as? String)
                    ?? (dict["messageId"] as? String)
                    ?? (dict["message_id"] as? String)
                    ?? (dict["uuid"] as? String)
                if let id, let record = usageRecord(from: usage, id: id) {
                    return record
                }
            }
            for (_, v) in dict { stack.append(v) }
        } else if let arr = cur as? [Any] {
            for v in arr { stack.append(v) }
        }
    }

    return nil
}

private func usageRecord(from usage: [String: Any], id: String) -> MessageUsageRecord? {
    let input = intFrom(usage, key: "input_tokens") ?? 0
    let output = intFrom(usage, key: "output_tokens") ?? 0

    // Claude Code commonly emits these.
    var cacheCreate = intFrom(usage, key: "cache_creation_input_tokens") ?? 0
    let cacheRead = intFrom(usage, key: "cache_read_input_tokens") ?? 0

    // Some logs omit cache_creation_input_tokens but include a breakdown under cache_creation.
    if cacheCreate == 0, let cc = usage["cache_creation"] as? [String: Any] {
        let eph5m = intFrom(cc, key: "ephemeral_5m_input_tokens") ?? 0
        let eph1h = intFrom(cc, key: "ephemeral_1h_input_tokens") ?? 0
        cacheCreate = eph5m + eph1h
    }

    if input + output + cacheCreate + cacheRead <= 0 { return nil }
    return MessageUsageRecord(
        id: id,
        inputTokens: input,
        outputTokens: output,
        cacheCreationInputTokens: cacheCreate,
        cacheReadInputTokens: cacheRead
    )
}

private struct TokenWeights {
    let cacheCreationWeight: Double
    let cacheReadWeight: Double
}

// Calibrated defaults from observed local logs:
// - 5h window is most sensitive to cache-read burstiness, so use a more conservative weight.
// - 7d window includes longer-lived context reuse, so weight is higher.
private let dailyWeights = TokenWeights(cacheCreationWeight: 0.02, cacheReadWeight: 0.0030)
private let weeklyWeights = TokenWeights(cacheCreationWeight: 0.02, cacheReadWeight: 0.0212)

private func intFrom(_ dict: [String: Any], key: String) -> Int? {
    if let v = dict[key] as? Int { return v }
    if let v = dict[key] as? Double { return Int(v) }
    if let v = dict[key] as? String, let i = Int(v) { return i }
    return nil
}

private func extractISODate(from any: Any, key: String) -> Date? {
    guard let dict = any as? [String: Any], let value = dict[key] as? String else { return nil }
    return parseISO8601(value)
}

private func extractISODateDeep(from any: Any) -> Date? {
    var stack: [Any] = [any]
    var seen = 0
    while let cur = stack.popLast() {
        seen += 1
        if seen > 2000 { break }
        if let dict = cur as? [String: Any] {
            if let value = dict["timestamp"] as? String, let d = parseISO8601(value) { return d }
            if let value = dict["time"] as? String, let d = parseISO8601(value) { return d }
            for (_, v) in dict { stack.append(v) }
        } else if let arr = cur as? [Any] {
            for v in arr { stack.append(v) }
        }
    }
    return nil
}

private func parseISO8601(_ value: String) -> Date? {
    // Claude Code logs often include fractional seconds (e.g. 2026-02-14T03:46:50.563Z)
    // while other records may omit them.
    if let d = isoWithFraction.date(from: value) { return d }
    if let d = isoNoFraction.date(from: value) { return d }
    return nil
}

private let isoWithFraction: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let isoNoFraction: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

// MARK: - stats-cache.json schema (subset)

private struct StatsCache: Codable {
    var lastComputedDate: String?
    var dailyModelTokens: [DailyModelTokens]?
    var modelUsage: [String: ModelUsage]?
}

private struct DailyModelTokens: Codable {
    var date: String
    var tokensByModel: [String: Int]

    func dateAsDate(in calendar: Calendar) -> Date? {
        // stats-cache uses YYYY-MM-DD
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = calendar.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: date)
    }
}

private struct ModelUsage: Codable {
    var inputTokens: Int?
    var outputTokens: Int?
}
