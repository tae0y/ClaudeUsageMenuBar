# Claude Usage MenuBar for MacOS

A macOS menu bar app that shows an **estimated** Claude Code token usage for:
- Rolling **5-hour** window
- Rolling **7-day** window

This app is designed for personal accounts where org/admin usage APIs are not available.

## How It Works
- Reads local Claude Code logs and caches:
  - `~/.claude/projects/**/*.jsonl` (per-message usage)
  - `~/.claude/stats-cache.json` (optional; may lag)
- Computes rolling windows by scanning recent JSONL files and deduplicating by message id.

### Token Budget
Because official limits are not reliably exposed via a public API for personal accounts, the app uses a configurable **token budget**.

Defaults:
- Rolling 5h budget: `44,000`
- Rolling 7d budget: `308,000` (5h * 7)

You can change these at any time in the app via the `Budget` button.

### Refresh Interval
- Auto refresh: every 5 minutes
- Manual refresh: `Refresh` button

## How To Use

### Prerequisites
- Xcode Command Line Tools

### Build an app bundle
From the repo root (It takes few minutes): 
```bash
./scripts/make_app_bundle.sh
```

This creates:
- `./dist/ClaudeUsageMenuBar.app`

### Install into Applications
Install it system-wide:
```bash
sudo cp -R "./dist/ClaudeUsageMenuBar.app" "/Applications/"
```

Install it user-only:
```bash
cp -R "./dist/ClaudeUsageMenuBar.app" "$HOME/Applications/"
```

Then launch it once so macOS registers it.

### Auto-Start on Login

1. Open **System Settings**
2. Go to **General** -> **Login Items**
3. Under **Open at Login**, click **+**
4. Select `ClaudeUsageMenuBar.app` from `/Applications` (or `~/Applications`)

## Notes / Limitations
- All values are **estimates** derived from local logs.
- Usage may differ from what you see in the web UI if you also use Claude outside Claude Code.
- First load is optimized using a cached snapshot stored in Application Support.

## Data Storage
Settings are stored as JSON at:
- `~/Library/Application Support/ClaudeUsageMenuBar/settings.json`
