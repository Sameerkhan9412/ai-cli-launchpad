# Contributing

Thanks for helping. Small, focused pull requests are easiest to review.

## Setup

```powershell
git clone https://github.com/kumarlalitss166/ai-cli-launchpad.git
cd ai-cli-launchpad
Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
```

## Before opening a PR

```powershell
Invoke-Pester ./tests
Invoke-ScriptAnalyzer -Path ./launchers -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

Both must be clean. CI runs the same checks on Windows PowerShell 5.1, PowerShell 7 (Windows) and PowerShell 7 (Ubuntu).

## Guidelines

- **Compatibility:** code must run on Windows PowerShell 5.1 *and* PowerShell 7+. No `??`, `?.`, ternary or `-Parallel`.
- **Testability:** put logic in `lib/*.ps1` functions and keep launcher scripts thin. Every new function gets Pester tests.
- **Never touch user config destructively:** merge, back up, or skip — do not overwrite.
- **No secrets in code, tests or fixtures.** Use obviously fake keys like `tp-0123456789abcdef`.
- **Adding a provider:** create `lib/<Provider>.ps1` (endpoints, key detection, catalog, env) and `Start-ClaudeWith<Provider>.ps1`, reusing `Common.ps1` and `ModelSelector.ps1`.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/):

```text
feat: add Token Plan Europe endpoint
fix: keep existing env vars when merging settings
docs: explain -NoSettingsWrite
test: cover sk- key on token-plan URL
refactor: move dotenv parsing to Common.ps1
ci: run tests on pwsh ubuntu
```

## Reporting bugs

Open an issue with the bug template. Include `-DryRun` output (the key is masked) — never your real key.
