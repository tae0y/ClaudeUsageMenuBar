import Foundation

public struct AutoCredentials: Sendable {
    public let organizationID: String?
    public let organizationSource: String?
    public let sessionKey: String?
    public let sessionSource: String?

    public init(
        organizationID: String?,
        organizationSource: String?,
        sessionKey: String?,
        sessionSource: String?
    ) {
        self.organizationID = organizationID
        self.organizationSource = organizationSource
        self.sessionKey = sessionKey
        self.sessionSource = sessionSource
    }
}

public struct AutoCredentialDetector: Sendable {
    public init() {}

    public func detect() -> AutoCredentials {
        let org = detectOrganizationID()
        let session = detectSessionKey()
        return AutoCredentials(
            organizationID: org?.value,
            organizationSource: org?.source,
            sessionKey: session?.value,
            sessionSource: session?.source
        )
    }

    private func detectOrganizationID() -> (value: String, source: String)? {
        if let env = readEnv("CLAUDE_ORGANIZATION_ID") {
            return (env, "env:CLAUDE_ORGANIZATION_ID")
        }

        if let org = readOrgFromClaudeJSON() {
            return (org, "~/.claude.json")
        }

        if let org = readCookie(name: "lastActiveOrg") {
            return (org, "Claude Cookies:lastActiveOrg")
        }

        return nil
    }

    private func detectSessionKey() -> (value: String, source: String)? {
        if let env = readEnv("CLAUDE_SESSION_KEY") {
            return (env, "env:CLAUDE_SESSION_KEY")
        }

        for cookieName in ["sessionKey", "__Secure-next-auth.session-token", "next-auth.session-token"] {
            if let value = readCookie(name: cookieName) {
                return (value, "Claude Cookies:\(cookieName)")
            }
        }

        return nil
    }

    private func readOrgFromClaudeJSON() -> String? {
        let path = NSHomeDirectory() + "/.claude.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if let oauth = root["oauthAccount"] as? [String: Any],
           let org = oauth["organizationUuid"] as? String,
           !org.isEmpty {
            return org
        }

        if let org = root["organizationUuid"] as? String, !org.isEmpty {
            return org
        }

        return nil
    }

    private func readCookie(name: String) -> String? {
        let candidates = [
            NSHomeDirectory() + "/Library/Application Support/Claude/Cookies",
            NSHomeDirectory() + "/Library/Application Support/Arc/User Data/Default/Cookies",
            NSHomeDirectory() + "/Library/Application Support/Google/Chrome/Default/Cookies",
            NSHomeDirectory() + "/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cookies",
            NSHomeDirectory() + "/Library/Application Support/Microsoft Edge/Default/Cookies",
        ]

        for dbPath in candidates {
            guard FileManager.default.fileExists(atPath: dbPath) else { continue }

            let sql = "SELECT value FROM cookies WHERE host_key LIKE '%claude.ai%' AND name='\(name)' ORDER BY expires_utc DESC LIMIT 1;"
            if let value = runSQLite(dbPath: dbPath, sql: sql), !value.isEmpty {
                return value
            }
        }

        return nil
    }

    private func runSQLite(dbPath: String, sql: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbPath, sql]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == true ? nil : output
        } catch {
            return nil
        }
    }

    private func readEnv(_ key: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
