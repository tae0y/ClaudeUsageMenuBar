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

public enum ClaudeUsageError: LocalizedError {
    case invalidResponse
    case unauthorized
    case missingUsageFields

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "응답을 해석할 수 없습니다."
        case .unauthorized:
            return "인증 실패: Organization ID 또는 Session Key를 확인하세요."
        case .missingUsageFields:
            return "일간/주간 사용량 필드를 찾을 수 없습니다."
        }
    }
}
