import Foundation

public struct ClaudeAPIClient: Sendable {
    public init() {}

    public func fetchUsage(organizationID: String, sessionKey: String) async throws -> UsageSnapshot {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(organizationID)/usage") else {
            throw ClaudeUsageError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeUsageError.invalidResponse
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw ClaudeUsageError.unauthorized
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClaudeUsageError.invalidResponse
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageError.invalidResponse
        }

        let daily = findWindow(in: root, keys: ["daily", "one_day", "day"])
        let weekly = findWindow(in: root, keys: ["weekly", "seven_day", "week", "rolling_7d"])

        if daily == nil && weekly == nil {
            throw ClaudeUsageError.missingUsageFields
        }
        return UsageSnapshot(daily: daily, weekly: weekly)
    }

    private func findWindow(in root: [String: Any], keys: [String]) -> UsageWindow? {
        if let direct = extractWindow(from: root, keys: keys) {
            return direct
        }
        for nestedKey in ["rate_limits", "limits", "usage"] {
            if let nested = root[nestedKey] as? [String: Any],
               let value = extractWindow(from: nested, keys: keys) {
                return value
            }
        }
        return nil
    }

    private func extractWindow(from dictionary: [String: Any], keys: [String]) -> UsageWindow? {
        for key in keys {
            if let window = dictionary[key] as? [String: Any] {
                return parseWindow(window)
            }
        }
        return nil
    }

    private func parseWindow(_ payload: [String: Any]) -> UsageWindow {
        let used = int(from: payload, keys: ["token_count", "used_tokens", "consumed_tokens", "usage", "count"])
        let limit = int(from: payload, keys: ["token_limit", "max_tokens", "limit", "quota"])

        var utilization = double(from: payload, keys: ["utilization", "utilization_percentage", "percent_used", "percentage"])
        if let value = utilization, value > 1 {
            // Some APIs return percentage as 0...100.
            utilization = value / 100
        }

        let reset = date(from: payload, keys: ["reset_at", "resets_at", "window_end", "period_end"])
        return UsageWindow(usedTokens: used, tokenLimit: limit, utilization: utilization, resetAt: reset)
    }

    private func int(from dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dictionary[key] as? Int { return value }
            if let value = dictionary[key] as? Double { return Int(value) }
            if let value = dictionary[key] as? String, let parsed = Int(value) { return parsed }
        }
        return nil
    }

    private func double(from dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = dictionary[key] as? Double { return value }
            if let value = dictionary[key] as? Int { return Double(value) }
            if let value = dictionary[key] as? String, let parsed = Double(value) { return parsed }
        }
        return nil
    }

    private func date(from dictionary: [String: Any], keys: [String]) -> Date? {
        let iso = ISO8601DateFormatter()
        for key in keys {
            if let value = dictionary[key] as? String,
               let parsed = iso.date(from: value) {
                return parsed
            }
            if let value = dictionary[key] as? Double {
                return Date(timeIntervalSince1970: value)
            }
            if let value = dictionary[key] as? Int {
                return Date(timeIntervalSince1970: Double(value))
            }
        }
        return nil
    }
}
