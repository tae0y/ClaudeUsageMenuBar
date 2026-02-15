import SwiftUI

@main
struct ClaudeUsageMenuBarApp: App {
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra(viewModel.menuTitle, systemImage: "gauge.with.dots.needle.67percent") {
            MenuBarContentView(viewModel: viewModel)
                .onAppear { viewModel.onAppear() }
        }
        .menuBarExtraStyle(.window)
    }
}
