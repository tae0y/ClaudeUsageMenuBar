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
            return "~/.claude/stats-cache.json 파일을 찾을 수 없습니다. Claude Code를 실행한 뒤 다시 시도하세요."
        case .invalidStatsCache:
            return "~/.claude/stats-cache.json 파싱에 실패했습니다."
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

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        var daily = 0
        var weekly = 0

        let fromStats = computeFromStatsCache(cache: cache, calendar: calendar, today: today)
        daily = fromStats.daily
        weekly = fromStats.weekly

        // stats-cache.json sometimes lags behind actual usage. If today's data is missing,
        // fall back to scanning ~/.claude/projects/**/*.jsonl which includes per-message usage.
        var sourceDetails = "~/.claude/stats-cache.json"
        if daily == 0 && !fromStats.hasTodayEntry {
            let scanned = scanProjectsJSONL(now: now, calendar: calendar)
            daily = scanned.daily
            weekly = scanned.weekly
            sourceDetails = scanned.sourceDetails
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

private func scanProjectsJSONL(now: Date, calendar: Calendar) -> ProjectScanRollup {
    let projectsRoot = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/projects", isDirectory: true)
    let fm = FileManager.default

    let todayStart = calendar.startOfDay(for: now)
    let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
    let weekStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart

    var dailyMaxByMessageID: [String: Int] = [:]
    var weeklyMaxByMessageID: [String: Int] = [:]

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
        let (d, w, lineCount, didUse) = scanOneJSONL(url: entry.url, calendar: calendar, dayStart: todayStart, dayEnd: tomorrowStart, weekStart: weekStart)
        scannedLines += lineCount
        usedFallback = usedFallback || didUse

        for (id, total) in d {
            if (dailyMaxByMessageID[id] ?? 0) < total { dailyMaxByMessageID[id] = total }
        }
        for (id, total) in w {
            if (weeklyMaxByMessageID[id] ?? 0) < total { weeklyMaxByMessageID[id] = total }
        }
    }

    let daily = dailyMaxByMessageID.values.reduce(0, +)
    let weekly = weeklyMaxByMessageID.values.reduce(0, +)

    let suffix = usedFallback ? ", dedupe=max-by-message-id" : ""
    let detail = "~/.claude/projects/**/*.jsonl (candidates=\(candidateFiles), scanned=\(scannedFiles), lines=\(scannedLines)\(suffix))"
    return ProjectScanRollup(daily: daily, weekly: weekly, sourceDetails: detail)
}

private func scanOneJSONL(
    url: URL,
    calendar: Calendar,
    dayStart: Date,
    dayEnd: Date,
    weekStart: Date
) -> (daily: [String: Int], weekly: [String: Int], lineCount: Int, didUse: Bool) {
    guard let data = try? Data(contentsOf: url),
          let text = String(data: data, encoding: .utf8) else {
        return ([:], [:], 0, false)
    }

    var daily: [String: Int] = [:]
    var weekly: [String: Int] = [:]
    var lines = 0
    var didUse = false

    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
        lines += 1
        guard let lineData = rawLine.data(using: .utf8) else { continue }
        guard let any = try? JSONSerialization.jsonObject(with: lineData) else { continue }

        // Use outer timestamp if present; it's more consistent for filtering.
        let ts = extractISODate(from: any, key: "timestamp") ?? extractISODateDeep(from: any) // fallback
        guard let ts else { continue }

        if ts < weekStart || ts >= dayEnd { continue }

        guard let record = extractMessageUsage(any: any, timestamp: ts) else { continue }
        didUse = true

        let total = max(0, record.inputTokens + record.outputTokens)
        if ts >= dayStart && ts < dayEnd {
            if (daily[record.id] ?? 0) < total { daily[record.id] = total }
        }
        if ts >= weekStart && ts < dayEnd {
            if (weekly[record.id] ?? 0) < total { weekly[record.id] = total }
        }
    }

    return (daily, weekly, lines, didUse)
}

private struct MessageUsageRecord {
    let id: String
    let inputTokens: Int
    let outputTokens: Int
}

private func extractMessageUsage(any: Any, timestamp: Date) -> MessageUsageRecord? {
    // Walk dictionaries to find a nested object with keys: id + usage{input_tokens, output_tokens}
    var stack: [Any] = [any]
    var seen = 0

    while let cur = stack.popLast() {
        seen += 1
        if seen > 2000 { break } // safety guard

        if let dict = cur as? [String: Any] {
            if let id = dict["id"] as? String,
               let usage = dict["usage"] as? [String: Any] {
                let input = intFrom(usage, key: "input_tokens") ?? 0
                let output = intFrom(usage, key: "output_tokens") ?? 0
                if input > 0 || output > 0 {
                    return MessageUsageRecord(id: id, inputTokens: input, outputTokens: output)
                }
            }
            for (_, v) in dict { stack.append(v) }
        } else if let arr = cur as? [Any] {
            for v in arr { stack.append(v) }
        }
    }

    return nil
}

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
