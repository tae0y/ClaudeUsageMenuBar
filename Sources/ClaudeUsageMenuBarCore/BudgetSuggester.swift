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
        // User-provided defaults:
        // - Daily budget: 44,000 tokens per 5-hour window
        // - Weekly budget: 7-day budget based on the above daily number
        let daily = 44_000
        let weekly = daily * 7
        return SuggestedBudgets(
            dailyTokenBudget: daily,
            weeklyTokenBudget: weekly,
            sourceDescription: "default: daily(5h)=44,000; weekly=7d"
        )
    }
}

// NOTE: We intentionally keep this suggester simple and stable.
// If you want an adaptive budget later, reintroduce stats-cache-based heuristics.
