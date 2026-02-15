import Foundation

public struct UsageWindow: Sendable {
    public let usedTokens: Int?
    public let tokenLimit: Int?
    public let utilization: Double?
    public let resetAt: Date?

    public init(usedTokens: Int?, tokenLimit: Int?, utilization: Double?, resetAt: Date?) {
        self.usedTokens = usedTokens
        self.tokenLimit = tokenLimit
        self.utilization = utilization
        self.resetAt = resetAt
    }

    public var progress: Double? {
        if let utilization {
            return max(0, min(utilization, 1))
        }
        if let usedTokens, let tokenLimit, tokenLimit > 0 {
            return max(0, min(Double(usedTokens) / Double(tokenLimit), 1))
        }
        return nil
    }
}

public struct UsageSnapshot: Sendable {
    public let daily: UsageWindow?
    public let weekly: UsageWindow?
    public let fetchedAt: Date

    public init(daily: UsageWindow?, weekly: UsageWindow?, fetchedAt: Date = .now) {
        self.daily = daily
        self.weekly = weekly
        self.fetchedAt = fetchedAt
    }
}
