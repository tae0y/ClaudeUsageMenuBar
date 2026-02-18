# Settings

Click **Configure** in the popover to open the settings sheet.

## Reset Time Anchors

The app computes window boundaries from a fixed anchor point rather than a rolling "from now" offset. Set the anchor to the last known reset time, and the app will derive all future cycle boundaries automatically.

| Field | Format | Example |
|-------|--------|---------|
| Daily anchor | `YYYY-MM-DD HH:mm` | `2026-02-18 09:00` |
| Weekly anchor | `YYYY-MM-DD HH:mm` | `2026-02-16 09:00` |

- **Daily**: cycles every **5 hours** from the anchor. Usage shown = tokens since the most recent 5h boundary.
- **Weekly**: cycles every **7 days** from the anchor. Usage shown = tokens since the most recent 7d boundary.
- Leave blank to use a pure rolling window (daily = last 5h from now, weekly = last 7d from now).

## Token Budget

Set the maximum token count for each window. Changing the plan multiplier (e.g. Claude Max ×5) means multiplying the default limits accordingly.

| Field | Default |
|-------|---------|
| Daily Budget (5h) | 44,000 |
| Weekly Budget (7d) | 1,478,400 |

## Cache Token Weights

Claude Code logs cache tokens separately from input/output tokens. Raw cache counts are not directly comparable to regular tokens for the purpose of estimating usage percentage, so the app applies scaling weights before summing.

| Field | Default | Description |
|-------|---------|-------------|
| 5h cache_creation weight | `0.02` | Weight for `cache_creation_input_tokens` in the daily window |
| 5h cache_read weight | `0.00133` | Weight for `cache_read_input_tokens` in the daily window |
| 7d cache_creation weight | `0.02` | Weight for `cache_creation_input_tokens` in the weekly window |
| 7d cache_read weight | `0.0165` | Weight for `cache_read_input_tokens` in the weekly window |

Leave any field blank to use the built-in default.

**When to adjust**: if the app's estimated percentage is consistently higher or lower than the actual usage shown on the Claude website, scale the weights down or up proportionally. For example, if the app shows 43% but actual is 33%, multiply weights by `33 ÷ 43 ≈ 0.77`.

Weighted token formula used internally:

```
weighted = (input + output)
         + cache_creation × cache_creation_weight
         + cache_read     × cache_read_weight
```

## Notes and Limitations

- All values are **estimates** derived from local logs.
- Usage may differ from the web UI if you also use Claude outside Claude Code.
- First load is optimized using a cached snapshot stored in Application Support.
- Settings are stored at: `~/Library/Application Support/ClaudeUsageMenuBar/settings.json`
