## What and why

<!-- One or two sentences. Link the issue: Closes #123 -->

## How I tested

- [ ] `Invoke-Pester ./tests` passes
- [ ] `Invoke-ScriptAnalyzer -Path ./launchers -Recurse -Settings ./PSScriptAnalyzerSettings.psd1` is clean
- [ ] Tried it manually (`-DryRun` or real launch) on: <!-- Windows PowerShell 5.1 / pwsh 7 / OS -->

## Checklist

- [ ] Works on Windows PowerShell 5.1 and PowerShell 7+
- [ ] New logic lives in `lib/` with tests
- [ ] User config is merged / backed up, never overwritten
- [ ] No keys or personal paths in code, tests or docs
- [ ] `CHANGELOG.md` updated under **Unreleased**
