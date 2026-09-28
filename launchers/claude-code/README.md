# Claude Code + Xiaomi MiMo launcher

Run Claude Code CLI on Xiaomi MiMo models (v2.6 Pro with 1M context, v2.6 Flash) instead of an Anthropic subscription.

| File | Role |
|---|---|
| `Start-ClaudeWithMiMo.ps1` | **Daily launcher.** Detects endpoint from your key, shows model menu, starts `claude` |
| `Configure-ClaudeWithMiMo.ps1` | One-time setup so plain `claude` also uses MiMo (from any terminal / IDE) |
| `lib/` | Shared helpers — do not run directly |
| `env.example` | Template for your key → copy to `.env` |

## 1. Prerequisites

- **PowerShell** 5.1 (built into Windows 10/11) or 7+ (`winget install Microsoft.PowerShell`, or your OS package manager)
- **Claude Code** on PATH — check with `claude --version`

  ```powershell
  irm https://claude.ai/install.ps1 | iex          # Windows native installer
  # or with Node 18+:
  npm install -g @anthropic-ai/claude-code
  ```
- **MiMo API key** — `tp-...` (Token Plan) or `sk-...` (pay-as-you-go) from the MiMo console

## 2. Setup (once)

```powershell
cd ai-cli-launchpad/launchers/claude-code

# Windows only, if you downloaded a ZIP or scripts are blocked:
Get-ChildItem -Recurse *.ps1 | Unblock-File
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

Copy-Item env.example .env
notepad .env                      # MIMO_TOKEN_PLAN_API_KEY=tp-...

# optional: make plain `claude` use MiMo everywhere
.\Configure-ClaudeWithMiMo.ps1
```

Open a **new** terminal after `Configure-ClaudeWithMiMo.ps1`.

## 3. Daily use

```powershell
cd D:\work\my-project
& "<repo>\launchers\claude-code\Start-ClaudeWithMiMo.ps1"
```

- **First run:** pick a model (recommended `mimo-v2.6-pro[1m]`). Saved to `preferences.json` next to the script.
- **Later:** Enter = saved model, `m` = change.
- In Claude Code run `/status` — Base URL should be `*.xiaomimimo.com`.

Tip: add a profile function so you can type `mimo` anywhere:

```powershell
# notepad $PROFILE
function mimo { & "C:\path\to\ai-cli-launchpad\launchers\claude-code\Start-ClaudeWithMiMo.ps1" @args }
```

## Options

### Start-ClaudeWithMiMo.ps1

| Parameter | Default | Meaning |
|---|---|---|
| `-Model <id or alias>` | saved / `mimo-v2.6-pro[1m]` | Skip the menu for this run. Aliases: `pro1m`, `pro`, `flash`, `v2.5-pro`, … |
| `-SelectModel` | off | Always show the menu |
| `-Plan <Auto\|PayAsYouGo\|TokenPlanSgp\|TokenPlanCn\|TokenPlanAms>` | `Auto` | Force endpoint instead of key-prefix detection |
| `-WorkingDirectory <path>` | current folder | Where Claude Code opens |
| `-NoSettingsWrite` | off | Session env only; don't touch `~/.claude/settings.json` |
| `-DryRun` | off | Print resolved config and exit — nothing written, `claude` not started |
| anything after `--` | | Passed straight to `claude` (e.g. `-- -p "summarize this repo"`) |

### Configure-ClaudeWithMiMo.ps1

| Parameter | Meaning |
|---|---|
| `-Plan` | Same as above |
| `-Model` | Main model id / alias (fast model follows the catalog) |
| `-ApiKey` | Key on the command line (lands in shell history — prefer `.env` or the hidden prompt) |

## What gets written

| File | Change |
|---|---|
| `.env` (this folder) | Your key. Gitignored. |
| `preferences.json` (this folder) | Saved default model. Gitignored. |
| `~/.claude/settings.json` | `env` block (Base URL, token, model slots, cache TTL) and cache settings **merged in**; every other key kept. Previous file backed up as `settings.backup-<time>.json` (last 5 kept). |
| `~/.claude.json` | Only `"hasCompletedOnboarding": true` is added (skips the Anthropic login screen). Nothing else in the file changes. |

`CLAUDE_CONFIG_DIR` is honored if you use a custom Claude config folder.

Env set for Claude Code:

| Variable | Value |
|---|---|
| `ANTHROPIC_BASE_URL` | MiMo Anthropic-compatible endpoint |
| `ANTHROPIC_AUTH_TOKEN` | your key |
| `ANTHROPIC_API_KEY` | cleared, so it cannot override the token |
| `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_OPUS_MODEL` | main model |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL`, `ANTHROPIC_SMALL_FAST_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL` | fast model |
| `ENABLE_PROMPT_CACHING_1H`, `CLAUDE_CODE_PROMPT_CACHE_TTL`, `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL` | 1-hour prompt cache |

## Undo

Restore the newest `~/.claude/settings.backup-*.json` over `~/.claude/settings.json`, or delete the `ANTHROPIC_*` entries from its `env` block. Then open a new terminal.

## Troubleshooting

See [docs/troubleshooting.md](https://github.com/kumarlalitss166/ai-cli-launchpad/blob/main/docs/troubleshooting.md). Most common:

| Symptom | Fix |
|---|---|
| `claude not found on PATH` | Install Claude Code, open a new terminal |
| `running scripts is disabled` | `Unblock-File` + `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| `Missing MiMo API key` | `.env` must sit next to the scripts and contain `MIMO_TOKEN_PLAN_API_KEY=...` |
| `400 token unavailable` / `401` | Key/plan mismatch or expired key — try `-DryRun` to see what was detected |
| Anthropic login menu appears | Ctrl+C, run `Configure-ClaudeWithMiMo.ps1`, open a new terminal |

> MiMo v2.5 models are marked legacy (retire 2026-10-21). Prefer v2.6.
