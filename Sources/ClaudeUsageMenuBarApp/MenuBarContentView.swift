import ClaudeUsageMenuBarCore
import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            usageSection(title: viewModel.dailyWindowLabel, window: viewModel.snapshot?.daily)
            usageSection(title: viewModel.weeklyWindowLabel, window: viewModel.snapshot?.weekly, includeEndDate: true)

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
                Button("Configure") {
                    viewModel.showingSettings = true
                }
                .popover(isPresented: $viewModel.showingSettings, arrowEdge: .bottom) {
                    LimitsView(viewModel: viewModel)
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 320)
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
    private func usageSection(title: String, window: UsageWindow?, includeEndDate: Bool = false) -> some View {
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
                        Text(endText(resetAt, includeDate: includeEndDate))
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

    private func endText(_ date: Date, includeDate: Bool) -> String {
        if includeDate {
            let style = Date.FormatStyle()
                .month(.abbreviated)
                .day(.defaultDigits)
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits)
            return "Ends \(date.formatted(style))"
        }
        return "Ends \(date.formatted(date: .omitted, time: .shortened))"
    }
}

private struct LimitsView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.title3.bold())

            Divider()

            Text("Reset Time Anchors")
                .font(.subheadline.bold())
            Text("Set the last known reset time. The app computes the next reset from that anchor on a fixed cycle (5h / 7d). Leave blank to use app-start as anchor.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Daily anchor (YYYY-MM-DD HH:mm)")
                .font(.caption)
            TextField("e.g. 2026-02-18 09:00", text: $viewModel.dailyAnchorInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))

            Text("Weekly anchor (YYYY-MM-DD HH:mm)")
                .font(.caption)
            TextField("e.g. 2026-02-16 09:00", text: $viewModel.weeklyAnchorInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))

            Divider()

            Text("Token Budget (Estimated Mode)")
                .font(.subheadline.bold())

            Text("Daily Budget (tokens)")
                .font(.caption)
            TextField("e.g. 44,000", text: $viewModel.dailyLimitInput)
                .textFieldStyle(.roundedBorder)

            Text("Weekly Budget (tokens)")
                .font(.caption)
            TextField("e.g. 1,478,400", text: $viewModel.weeklyLimitInput)
                .textFieldStyle(.roundedBorder)

            Text("Defaults are prefilled and can be changed at any time.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let error = viewModel.errorMessage {
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
