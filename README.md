# Claude Usage MenuBar

A native macOS menu bar app that shows **estimated** Claude Code token usage in two rolling windows: **5-hour** (daily) and **7-day** (weekly).

Designed for personal accounts where org/admin usage APIs are not available.

## How It Works

- Reads local Claude Code logs:
  - `~/.claude/projects/**/*.jsonl` — per-message usage (primary source)
  - `~/.claude/stats-cache.json` — fallback if JSONL yields no data
- Deduplicates entries by message ID and applies rolling window cutoffs
- Applies window-specific weights to cache tokens to reduce spike bias

### Token Budget

Official limits are not exposed via public API for personal accounts, so the app uses a configurable token budget.

Default budgets:

| Window | Default | Basis |
|--------|---------|-------|
| Rolling 5h | 44,000 | — |
| Rolling 7d | 1,478,400 | `44,000 × (7×24÷5)` (33.6 rolling windows) |

You can change these at any time via the **Budget** button in the app.

### Refresh

- Auto refresh: every **5 minutes**
- Manual refresh: **Refresh** button

## Prerequisites

- macOS 14 or later
- Xcode Command Line Tools

    ```bash
    xcode-select --install
    ```

## Getting Started

### Build and debug

1. Clone the repository.

    ```bash
    git clone https://github.com/your-username/ClaudeUsageMenuBar.git
    cd ClaudeUsageMenuBar
    ```

1. Run the app in debug mode (CLI only — no menu bar icon).

    ```bash
    swift run
    ```

### Build and install

1. Build the `.app` bundle (takes a few minutes).

    ```bash
    ./scripts/make_app_bundle.sh
    ```

    This creates `./dist/ClaudeUsageMenuBar.app`.

1. Install the app.

    - **User-only** (recommended):

        ```bash
        cp -R "./dist/ClaudeUsageMenuBar.app" "$HOME/Applications/"
        ```

    - **System-wide**:

        ```bash
        sudo cp -R "./dist/ClaudeUsageMenuBar.app" "/Applications/"
        ```

1. Launch the app once so macOS registers it.

### Enable auto-start on login

1. Open **System Settings**.
1. Go to **General** → **Login Items**.
1. Under **Open at Login**, click **+**.
1. Select `ClaudeUsageMenuBar.app` from `/Applications` or `~/Applications`.

> If the app does not appear in the picker, open `~/Applications` in Finder and drag `ClaudeUsageMenuBar.app` directly into the **Open at Login** list. Launch the app once and try again if needed.

## Notes and Limitations

- All values are **estimates** derived from local logs.
- Usage may differ from the web UI if you also use Claude outside Claude Code.
- First load is optimized using a cached snapshot stored in Application Support.
- Settings are stored at: `~/Library/Application Support/ClaudeUsageMenuBar/settings.json`
