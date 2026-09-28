# Troubleshooting

Start with a dry run — it shows what was detected without changing anything (key is masked):

```powershell
.\Start-ClaudeWithMiMo.ps1 -DryRun
```

## Script will not run

| Message | Cause | Fix |
|---|---|---|
| `running scripts is disabled on this system` | Windows execution policy | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| `... is not digitally signed` / `cannot be loaded` | File downloaded from the internet (Mark of the Web) | `Get-ChildItem -Recurse *.ps1 \| Unblock-File` |
| `The term '...\lib\Common.ps1' is not recognized` | Script copied without the `lib/` folder | Keep `lib/` next to the launcher |

## Key problems

| Message | Fix |
|---|---|
| `Missing MiMo API key` | `.env` must be **next to the script** with `MIMO_TOKEN_PLAN_API_KEY=...` (or set that env var) |
| `sk- (pay-as-you-go) key cannot use a Token Plan Base URL` | Remove `-Plan TokenPlan*`, or use a `tp-` key |
| `tp- (Token Plan) key cannot use the pay-as-you-go Base URL` | Remove `-Plan PayAsYouGo`, or use an `sk-` key |
| Wrong key picked up | Order is: env `MIMO_TOKEN_PLAN_API_KEY` → `.env` → env/.env `MIMO_API_KEY`. The dry run prints the source. Clear stale env vars with `Remove-Item Env:MIMO_TOKEN_PLAN_API_KEY` |

## Claude Code problems

| Symptom | Fix |
|---|---|
| `claude not found on PATH` | Install Claude Code, then open a **new** terminal |
| Anthropic login menu (subscription / Console / Bedrock) | Ctrl+C. Run `Configure-ClaudeWithMiMo.ps1`, open a new terminal |
| `/status` shows an Anthropic URL | An old terminal kept old env. Close all terminals; relaunch |
| `400 token unavailable` | Key/URL mismatch or Token Plan quota used up. Check the dry run and your MiMo console |
| `401` | Key revoked / mistyped. Re-create it and update `.env` |
| Model not found | Model id retired or mistyped. `-SelectModel` and pick from the catalog |
| Region latency | Token Plan keys can use `-Plan TokenPlanCn` or `-Plan TokenPlanAms` if your plan page lists that region |

## Restore previous Claude settings

```powershell
Get-ChildItem ~/.claude/settings.backup-*.json | Sort-Object Name -Descending | Select-Object -First 1 |
    Copy-Item -Destination ~/.claude/settings.json -Force
```

## Still stuck

Open an issue with the bug template and paste the `-DryRun` output. **Never** paste your key.
