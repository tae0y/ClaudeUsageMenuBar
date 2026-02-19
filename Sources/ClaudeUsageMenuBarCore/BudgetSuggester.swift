import Foundation

public struct SuggestedBudgets: Sendable {
    public let dailyTokenBudget: Int
    public let weeklyTokenBudget: Int
    public let sourceDescription: String

    public init(dailyTokenBudget: Int, weeklyTokenBudget: Int, sourceDescription: String) {
        self.dailyTokenBudget = dailyTokenBudget
        self.weeklyTokenBudget = weeklyTokenBudget
        self.sourceDescription = sourceDescription
    }
}

public struct BudgetSuggester: Sendable {
    public init() {}

    public func suggest(now: Date = .now) -> SuggestedBudgets {
        // Max 5× subscription: base budget 44,000 × 5 = 220,000 per 5-hour window.
        // Weekly budget: 7 days = 168 hours, 168 / 5 = 33.6 windows.
        let daily = 220_000
        let weekly = Int((Double(daily) * (7.0 * 24.0 / 5.0)).rounded())
        return SuggestedBudgets(
            dailyTokenBudget: daily,
            weeklyTokenBudget: weekly,
            sourceDescription: "default: daily(5h)=220,000(5×); weekly(7d)=daily*33.6"
        )
    }
}

// NOTE: We intentionally keep this suggester simple and stable.
// If you want an adaptive budget later, reintroduce stats-cache-based heuristics.
