# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) · Versioning: [SemVer](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-09-28

### Added
- Both scripts check that Claude Code is installed. If `claude` is missing they offer to install it
  (official installer, or npm when Node is present), reload PATH and continue in the same run.
- `-InstallClaude` (install without asking) and `-SkipClaudeInstall` (never offer) switches.
- `CLAUDE` line in the launcher banner shows where `claude` was found.

## [0.1.0] - 2026-09-28

### Added
- `Start-ClaudeWithMiMo.ps1` — launch Claude Code on Xiaomi MiMo with endpoint auto-detection from key prefix (`tp-`/`ttp-` Token Plan, `sk-` pay-as-you-go).
- Key/endpoint mismatch guard with a clear error instead of an API 400/401.
- Interactive model picker with saved default per machine (`preferences.json`), aliases (`pro1m`, `pro`, `flash`) and custom model ids.
- `-DryRun` and `-NoSettingsWrite` switches; pass-through of extra args to `claude`.
- `Configure-ClaudeWithMiMo.ps1` — one-time global setup with hidden key prompt.
- Shared `lib/` (Common, MiMo, ModelSelector) usable by future provider launchers.
- `CLAUDE_CONFIG_DIR` support.
- Pester test suite, PSScriptAnalyzer config, GitHub Actions CI (Windows PowerShell 5.1, pwsh on Windows and Linux, secret scan).

### Security
- `~/.claude/settings.json` is merged instead of overwritten; previous file backed up (last 5 kept).
- `~/.claude.json` is edited as text to add only `hasCompletedOnboarding`, preserving project trust and MCP servers.
- Keys are masked in all console output.

[Unreleased]: https://github.com/kumarlalitss166/ai-cli-launchpad/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/kumarlalitss166/ai-cli-launchpad/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/kumarlalitss166/ai-cli-launchpad/releases/tag/v0.1.0
