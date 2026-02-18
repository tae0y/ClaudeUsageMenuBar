import ClaudeUsageMenuBarCore
import Foundation

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var sourceStatus = "Local estimate pending"
    @Published var burnRateStatus = "-"
    @Published var showingSettings = false
    @Published var dailyLimitInput = ""
    @Published var weeklyLimitInput = ""
    /// "YYYY-MM-DD HH:mm" string the user types for the daily anchor
    @Published var dailyAnchorInput = ""
    /// "YYYY-MM-DD HH:mm" string the user types for the weekly anchor
    @Published var weeklyAnchorInput = ""

    private let estimator = LocalUsageEstimator()
    private var timer: Timer?
    private let settingsStore = SettingsStore()
    private var settings: AppSettings
    private let budgetSuggester = BudgetSuggester()

    // For burn rate (tokens/min) estimation since app start.
    // Use lifetime tokens to avoid "rolling window drops" making this negative/noisy.
    private var lastLifetimeTokens: Int?
    private var lastLifetimeAt: Date?

    init() {
        self.settings = settingsStore.load()

        // One-time migration for old defaults:
        // legacy weekly defaults were 308,000 (daily*7) and 2,000,000 (placeholder-era value).
        // new: weekly is derived from 5h windows across 7d => daily*33.6 (1,478,400 when daily is 44,000)
        if settings.dailyTokenLimit == 44_000,
           settings.weeklyTokenLimit == 308_000 || settings.weeklyTokenLimit == 2_000_000 {
            let suggested = budgetSuggester.suggest()
            settings.weeklyTokenLimit = suggested.weeklyTokenBudget
            try? settingsStore.save(settings)
        }

        if settings.dailyTokenLimit == nil || settings.weeklyTokenLimit == nil {
            let suggested = budgetSuggester.suggest()
            // Only fill missing fields (user can change later).
            if settings.dailyTokenLimit == nil { settings.dailyTokenLimit = suggested.dailyTokenBudget }
            if settings.weeklyTokenLimit == nil { settings.weeklyTokenLimit = suggested.weeklyTokenBudget }
            try? settingsStore.save(settings)
        }

        if let d = settings.dailyTokenLimit { dailyLimitInput = String(d) }
        if let w = settings.weeklyTokenLimit { weeklyLimitInput = String(w) }
        dailyAnchorInput = settings.dailyAnchorDate.map { anchorInputFormatter.string(from: $0) } ?? ""
        weeklyAnchorInput = settings.weeklyAnchorDate.map { anchorInputFormatter.string(from: $0) } ?? ""

        // Show cached snapshot immediately to avoid "blank" first paint.
        if let cached = settings.lastSnapshot {
            let dailyEndAt = nextDailyReset(after: cached.fetchedAt)
            let weeklyEndAt = nextWeeklyReset(after: cached.fetchedAt)
            let daily = UsageWindow(usedTokens: cached.dailyTokens, tokenLimit: settings.dailyTokenLimit, utilization: nil, resetAt: dailyEndAt)
            let weekly = UsageWindow(usedTokens: cached.weeklyTokens, tokenLimit: settings.weeklyTokenLimit, utilization: nil, resetAt: weeklyEndAt)
            self.snapshot = UsageSnapshot(daily: daily, weekly: weekly, fetchedAt: cached.fetchedAt)
            self.sourceStatus = "Estimated (cached): \(cached.sourceDescription)"
        }
    }

    var dailyWindowLabel: String { "5h (rolling)" }
    var weeklyWindowLabel: String { "7d (rolling)" }

    var menuTitle: String {
        // Keep title short; show 5h budget utilization as a percentage.
        guard snapshot != nil else { return "Claude" }
        return "( ᐛ )σ \(dailyPercentUsedText)"
    }

    var dailyProgress: Double? {
        snapshot?.daily?.progress
    }

    var dailyPercentUsedText: String {
        guard let p = dailyProgress else { return "-%" }
        let used = max(0, min(p, 1)) * 100
        return "\(Int(used.rounded()))%"
    }

    var dailyPercentLeftText: String {
        guard let p = dailyProgress else { return "-" }
        let remaining = max(0, min(1 - p, 1)) * 100
        return "\(Int(remaining.rounded()))% left"
    }

    func onAppear() {
        Task { await refresh() }
        startTimer()
    }

    func saveLimits() {
        let dailyRaw = dailyLimitInput
        let weeklyRaw = weeklyLimitInput
        let daily = parseTokenLimit(dailyRaw)
        let weekly = parseTokenLimit(weeklyRaw)

        // If user typed something but it didn't parse, keep the sheet open and show an error.
        if daily == nil && !dailyRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Invalid daily budget. Use digits only (commas/underscores/spaces are allowed). Example: 44000 or 44,000."
            return
        }
        if weekly == nil && !weeklyRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Invalid weekly budget. Use digits only (commas/underscores/spaces are allowed). Example: 1478400 or 1,478,400."
            return
        }

        // Validate anchor dates.
        let dailyAnchorRaw = dailyAnchorInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let weeklyAnchorRaw = weeklyAnchorInput.trimmingCharacters(in: .whitespacesAndNewlines)

        var dailyAnchor: Date? = nil
        if !dailyAnchorRaw.isEmpty {
            guard let d = anchorInputFormatter.date(from: dailyAnchorRaw) else {
                errorMessage = "Invalid daily reset time. Use format: YYYY-MM-DD HH:mm (e.g. 2026-02-18 09:00)"
                return
            }
            dailyAnchor = d
        }

        var weeklyAnchor: Date? = nil
        if !weeklyAnchorRaw.isEmpty {
            guard let d = anchorInputFormatter.date(from: weeklyAnchorRaw) else {
                errorMessage = "Invalid weekly reset time. Use format: YYYY-MM-DD HH:mm (e.g. 2026-02-18 09:00)"
                return
            }
            weeklyAnchor = d
        }

        settings.dailyTokenLimit = (daily != nil && daily! > 0) ? daily : nil
        settings.weeklyTokenLimit = (weekly != nil && weekly! > 0) ? weekly : nil
        settings.dailyAnchorDate = dailyAnchor
        settings.weeklyAnchorDate = weeklyAnchor

        do {
            try settingsStore.save(settings)
        } catch {
            errorMessage = "Failed to save settings: \(error.localizedDescription)"
            return
        }

        errorMessage = nil
        showingSettings = false
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let now = Date()
            // File scanning can be heavy; do it off the main thread.
            let weeklyStart = currentWeeklyWindowStart(at: now)
            let estimate = try await Task.detached(priority: .utility) { [estimator, weeklyStart] in
                try estimator.estimate(weeklyWindowStart: weeklyStart)
            }.value
            let dailyLimit = settings.dailyTokenLimit
            let weeklyLimit = settings.weeklyTokenLimit

            let daily = UsageWindow(
                usedTokens: estimate.dailyTokens,
                tokenLimit: dailyLimit,
                utilization: nil,
                resetAt: nextDailyReset(after: now)
            )
            let weekly = UsageWindow(
                usedTokens: estimate.weeklyTokens,
                tokenLimit: weeklyLimit,
                utilization: nil,
                resetAt: nextWeeklyReset(after: now)
            )

            snapshot = UsageSnapshot(daily: daily, weekly: weekly)
            sourceStatus = "Estimated: \(estimate.sourceDescription)"
            burnRateStatus = burnRateString(lifetimeTokens: estimate.lifetimeTotalTokens)

            // Persist last snapshot for fast next startup.
            settings.lastSnapshot = PersistedSnapshot(
                dailyTokens: estimate.dailyTokens,
                weeklyTokens: estimate.weeklyTokens,
                fetchedAt: Date(),
                sourceDescription: estimate.sourceDescription
            )
            try? settingsStore.save(settings)

            errorMessage = nil
        } catch {
            snapshot = nil
            sourceStatus = "Estimated: unavailable"
            burnRateStatus = "-"
            errorMessage = error.localizedDescription
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.refresh() }
        }
    }

    private func parseTokenLimit(_ raw: String) -> Int? {
        // Accept common formatting: "500,000", "500_000", " 500000 "
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
        return Int(normalized)
    }

    private func burnRateString(lifetimeTokens: Int) -> String {
        let now = Date()
        defer {
            lastLifetimeTokens = lifetimeTokens
            lastLifetimeAt = now
        }

        guard let prev = lastLifetimeTokens, let prevAt = lastLifetimeAt else {
            return "Burn: -"
        }

        let delta = lifetimeTokens - prev
        let minutes = max(now.timeIntervalSince(prevAt) / 60.0, 0.0001)
        let rate = Double(delta) / minutes

        if rate.isNaN || rate.isInfinite || rate < 0 {
            return "Burn: -"
        }

        return "Burn: \(Int(rate.rounded())) tok/min"
    }

    /// Returns the next daily reset time after `date`.
    /// Logic: find the most recent past anchor (anchor + N*5h ≤ date), then add 5h.
    private func nextDailyReset(after date: Date) -> Date {
        let intervalSec: TimeInterval = 5 * 60 * 60
        guard let anchor = settings.dailyAnchorDate else {
            // No anchor configured — synthetic rolling window from now.
            return date.addingTimeInterval(intervalSec)
        }
        // How many full 5h cycles have elapsed since anchor?
        let elapsed = date.timeIntervalSince(anchor)
        let cyclesPassed = floor(elapsed / intervalSec)
        let lastReset = anchor.addingTimeInterval(cyclesPassed * intervalSec)
        return lastReset.addingTimeInterval(intervalSec)
    }

    /// Returns the start of the current weekly window (= last reset time).
    /// When anchor is set: anchor + N*7d ≤ date (most recent cycle boundary).
    /// When unset: now - 7d (pure rolling).
    func currentWeeklyWindowStart(at date: Date) -> Date {
        let intervalSec: TimeInterval = 7 * 24 * 60 * 60
        guard let anchor = settings.weeklyAnchorDate else {
            return date.addingTimeInterval(-intervalSec)
        }
        let elapsed = date.timeIntervalSince(anchor)
        let cyclesPassed = floor(elapsed / intervalSec)
        return anchor.addingTimeInterval(cyclesPassed * intervalSec)
    }

    /// Returns the next weekly reset time after `date`.
    /// Logic: find the most recent past anchor (anchor + N*7d ≤ date), then add 7d.
    private func nextWeeklyReset(after date: Date) -> Date {
        let intervalSec: TimeInterval = 7 * 24 * 60 * 60
        guard let anchor = settings.weeklyAnchorDate else {
            // No anchor configured — fall back to Sunday 15:00 Asia/Seoul.
            return nextSundaySeoulReset(after: date)
        }
        let elapsed = date.timeIntervalSince(anchor)
        let cyclesPassed = floor(elapsed / intervalSec)
        let lastReset = anchor.addingTimeInterval(cyclesPassed * intervalSec)
        return lastReset.addingTimeInterval(intervalSec)
    }

    private func nextSundaySeoulReset(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        var components = DateComponents()
        components.weekday = 1 // Sunday
        components.hour = 15
        components.minute = 0
        components.second = 0

        if let next = calendar.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) {
            return next
        }
        return date.addingTimeInterval(7 * 24 * 60 * 60)
    }

    private func compactToken(_ value: Int?) -> String {
        guard let value else { return "-" }
        if value >= 1_000_000 {
            return String(format: "%.1fm", Double(value) / 1_000_000.0)
        }
        if value >= 10_000 {
            return String(format: "%.1fk", Double(value) / 1_000.0)
        }
        if value >= 1_000 {
            return String(format: "%.0fk", Double(value) / 1_000.0)
        }
        return String(value)
    }
}

// MARK: - Shared formatter

private let anchorInputFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    // Use local timezone so user inputs local time.
    f.timeZone = TimeZone.current
    return f
}()
