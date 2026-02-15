import ClaudeUsageMenuBarCore
import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            usageSection(title: "5h (rolling)", window: viewModel.snapshot?.daily)
            usageSection(title: "7d (rolling)", window: viewModel.snapshot?.weekly)

            Text(viewModel.burnRateStatus)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(viewModel.sourceStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Refresh") {
                    Task { await viewModel.refresh() }
                }
                Button("Budget") {
                    viewModel.showingSettings = true
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 320)
        .sheet(isPresented: $viewModel.showingSettings) {
            LimitsView(viewModel: viewModel)
        }
    }

    private var header: some View {
        HStack {
            Text("Claude Code Usage")
                .font(.headline)
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
    }

    @ViewBuilder
    private func usageSection(title: String, window: UsageWindow?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.bold())

            if let window {
                ProgressView(value: window.progress ?? 0)
                    .opacity(window.progress == nil ? 0 : 1)

                HStack {
                    Text(tokenText(window))
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Text(remainingText(window))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let resetAt = window.resetAt {
                        Text(resetAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tokenText(_ window: UsageWindow) -> String {
        let used = window.usedTokens.map { String($0) } ?? "-"
        let limit = window.tokenLimit.map { String($0) } ?? "-"
        if window.tokenLimit != nil {
            return "\(used) / \(limit) tok"
        }
        return "\(used) tok"
    }

    private func remainingText(_ window: UsageWindow) -> String {
        guard let p = window.progress else { return "-" }
        let remaining = max(0, min(1 - p, 1)) * 100
        return "\(Int(remaining.rounded()))% left"
    }
}

private struct LimitsView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Token Budget (Estimated Mode)")
                .font(.title3.bold())

            Text("5h Budget (tokens)")
                .font(.caption)
            TextField("e.g. 500000", text: $viewModel.dailyLimitInput)
                .textFieldStyle(.roundedBorder)

            Text("7d Budget (tokens)")
                .font(.caption)
            TextField("e.g. 2000000", text: $viewModel.weeklyLimitInput)
                .textFieldStyle(.roundedBorder)

            Text("Defaults are prefilled and can be changed at any time.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let error = viewModel.errorMessage, error.contains("Limit") {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Save") { viewModel.saveLimits() }
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}
