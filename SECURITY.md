# Security

## Where your key lives

| Location | Why | Protection |
|---|---|---|
| `launchers/claude-code/.env` | Launcher reads it | Listed in `.gitignore`; never commit it |
| `~/.claude/settings.json` (`env.ANTHROPIC_AUTH_TOKEN`) | How Claude Code reads provider credentials | Your user profile only |
| Process environment of the launching shell | Passed to `claude` | Ends with the session |

Keys are stored in **plain text** in these files — that is how Claude Code consumes them. Do not share, zip or screenshot your copy of the folder after adding `.env`, and do not paste keys in chats or issues.

Console output only ever shows a masked key (`tp-ab...1234`).

## What the scripts change outside this folder

- `~/.claude/settings.json` — merged, with a timestamped backup (last 5 kept).
- `~/.claude.json` — only the `hasCompletedOnboarding` flag is added; the rest of the file is left byte-for-byte as it was.

Use `-DryRun` to see what would be configured, or `-NoSettingsWrite` to keep changes to the current session.

## If a key leaks

1. Revoke / rotate it in the MiMo console immediately.
2. If it was committed, rotating is mandatory — rewriting git history does not un-leak a pushed secret.

## Reporting a vulnerability

Please use **GitHub → Security → Report a vulnerability** (private advisory) on this repository instead of a public issue. Expect a reply within 7 days.

CI runs [gitleaks](https://github.com/gitleaks/gitleaks) on every push and pull request.
