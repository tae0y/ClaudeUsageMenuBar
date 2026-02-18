# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**ClaudeUsageMenuBar** is a native macOS menu bar app (Swift/SwiftUI, macOS 14+) that monitors Claude Code token usage by scanning local JSONL logs. It tracks two rolling windows: 5-hour (daily) and 7-day (weekly).

## Build & Run

```bash
# Development (runs CLI, no menu bar icon)
swift run

# Production: build .app bundle into ./dist/
./scripts/make_app_bundle.sh

# Install to Applications
cp -R "./dist/ClaudeUsageMenuBar.app" "$HOME/Applications/"
```

No external dependencies — only Swift standard library + Apple frameworks (Foundation, SwiftUI, AppKit).

## Architecture

Two SPM targets:

**`ClaudeUsageMenuBarCore`** (library) — pure logic, no UI:
- [Models.swift](Sources/ClaudeUsageMenuBarCore/Models.swift) — `UsageWindow`, `UsageSnapshot` (UI-facing); `AppSettings`, `PersistedSnapshot` in [SettingsStore.swift](Sources/ClaudeUsageMenuBarCore/SettingsStore.swift)
- [LocalUsageEstimator.swift](Sources/ClaudeUsageMenuBarCore/LocalUsageEstimator.swift) — scans `~/.claude/projects/**/*.jsonl`, applies weighted token counting, deduplicates by message ID; also defines `LocalUsageEstimate` and `LocalUsageEstimatorError`
- [SettingsStore.swift](Sources/ClaudeUsageMenuBarCore/SettingsStore.swift) — persists `AppSettings` (limits, anchor dates, cached snapshot) to `~/Library/Application Support/ClaudeUsageMenuBar/settings.json`
- [BudgetSuggester.swift](Sources/ClaudeUsageMenuBarCore/BudgetSuggester.swift) — provides static defaults: daily=44,000, weekly=daily×33.6

**`ClaudeUsageMenuBarApp`** (executable):
- [AppMain.swift](Sources/ClaudeUsageMenuBarApp/AppMain.swift) — `@main` SwiftUI entry, `MenuBarExtra` integration; `LSUIElement=true` so it never shows in the Dock
- [UsageViewModel.swift](Sources/ClaudeUsageMenuBarApp/UsageViewModel.swift) — `@MainActor` ViewModel; 5-min auto-refresh timer; burn rate via lifetime token delta; `nextDailyReset`/`nextWeeklyReset` anchor-date arithmetic
- [MenuBarContentView.swift](Sources/ClaudeUsageMenuBarApp/MenuBarContentView.swift) — popover UI, progress bars, settings sheet

## Key Design Decisions

### Token Weighting
The estimator applies **different weights per window** to prevent distortion:
- Daily (5h): `cache_read × 0.00133`, `cache_creation × 0.02` — conservative, prevents spiky cache bursts inflating daily %
- Weekly (7d): `cache_read × 0.0165`, `cache_creation × 0.02` — captures longer-term cache reuse trends

```swift
// Weighted total = (input + output) + (cache_creation × w1) + (cache_read × w2)
```

### Data Flow
1. Scan JSONL logs → extract `message.id` + `message.usage` fields
2. Deduplicate by message ID (take max tokens per message)
3. Apply rolling window cutoffs (now−5h, now−7d)
4. Apply per-window token weights
5. Fallback to `~/.claude/stats-cache.json` if JSONL yields no data
6. Cache snapshot to settings for fast next-startup display

### Anchor Dates
Both windows support an optional user-configurable anchor date (stored in `AppSettings`). When set, reset times are computed as `anchor + N × interval` (next cycle boundary). When unset:
- Daily: rolling from now (reset = now + 5h)
- Weekly: next Sunday 15:00 Asia/Seoul

Anchor dates are input as `YYYY-MM-DD HH:mm` in the settings sheet and parsed in local timezone.

### Performance Limits
- Skips files older than 30 days
- Scans at most 200 files per refresh (most-recent first)
- Deep JSON search limited to 4000 objects (safety for nested structures)
