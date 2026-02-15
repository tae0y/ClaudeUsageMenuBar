import SwiftUI

@main
struct ClaudeUsageMenuBarApp: App {
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(viewModel: viewModel)
                .onAppear { viewModel.onAppear() }
        } label: {
            MenuBarLabelView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabelView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        HStack(spacing: 6) {
            DailyBudgetBar(progress: viewModel.dailyProgress)
            Text(viewModel.menuTitle)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .accessibilityLabel("Daily budget usage")
        .accessibilityValue(viewModel.dailyPercentLeftText)
    }
}

private struct DailyBudgetBar: View {
    let progress: Double?

    var body: some View {
        let p = min(max(progress ?? 0, 0), 1)
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.secondary.opacity(0.25))
            Capsule()
                .fill(color(for: p))
                .frame(width: 26 * p)
        }
        .frame(width: 26, height: 8)
    }

    private func color(for progress: Double) -> Color {
        switch progress {
        case ..<0.7: return .green
        case ..<0.9: return .yellow
        default: return .red
        }
    }
}
