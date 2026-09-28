#Requires -Version 5.1
<#
.SYNOPSIS
  Launch Claude Code on Xiaomi MiMo models (Token Plan or pay-as-you-go).

.DESCRIPTION
  1. Reads your MiMo key from .env next to this script (or the environment).
  2. Picks the Anthropic-compatible Base URL from the key prefix (tp-/ttp- Token Plan, sk- pay-as-you-go)
     and refuses key/URL combinations that can only fail with 400/401.
  3. Model menu on first run; the choice is saved in preferences.json (Enter reuses it later).
  4. Checks that Claude Code is installed; if not, asks whether to install it and carries on.
  5. Sets the env for this session, merges the same values into ~/.claude/settings.json
     (so plain `claude` also uses MiMo), then starts `claude` in -WorkingDirectory.

.PARAMETER Model
  Model id or alias (pro1m, pro, flash, ...). Skips the menu for this run.

.PARAMETER SelectModel
  Always show the model menu.

.PARAMETER Plan
  Force an endpoint instead of detecting it from the key prefix.

.PARAMETER WorkingDirectory
  Folder Claude Code opens in. Defaults to the current folder.

.PARAMETER NoSettingsWrite
  Only set env vars for this session; leave ~/.claude/settings.json untouched.

.PARAMETER DryRun
  Resolve and print the configuration. Writes nothing, installs nothing and does not start claude.

.PARAMETER InstallClaude
  If Claude Code is missing, install it with the recommended method without asking.

.PARAMETER SkipClaudeInstall
  If Claude Code is missing, print install steps and exit instead of offering to install.

.EXAMPLE
  .\Start-ClaudeWithMiMo.ps1

.EXAMPLE
  .\Start-ClaudeWithMiMo.ps1 -Model flash -WorkingDirectory D:\work\api

.EXAMPLE
  .\Start-ClaudeWithMiMo.ps1 -Plan PayAsYouGo -DryRun

.EXAMPLE
  .\Start-ClaudeWithMiMo.ps1 -- -p "explain this repo"    # everything after -- goes to claude
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Model,
    [switch]$SelectModel,
    [ValidateSet('Auto', 'PayAsYouGo', 'TokenPlanSgp', 'TokenPlanCn', 'TokenPlanAms')]
    [string]$Plan = 'Auto',
    [string]$WorkingDirectory = (Get-Location).Path,
    [switch]$NoSettingsWrite,
    [switch]$DryRun,
    [switch]$InstallClaude,
    [switch]$SkipClaudeInstall,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ClaudeArgs
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$EnvFile = Join-Path $Root '.env'

. (Join-Path $Root 'lib/Common.ps1')
. (Join-Path $Root 'lib/MiMo.ps1')
. (Join-Path $Root 'lib/ModelSelector.ps1')

$keyInfo = Resolve-MiMoApiKey -EnvFile $EnvFile
if (-not $keyInfo) {
    Write-Host ''
    Write-Host 'Missing MiMo API key.' -ForegroundColor Yellow
    Write-Host "  1. Copy env.example to .env in: $Root"
    Write-Host '  2. Set MIMO_TOKEN_PLAN_API_KEY=tp-...  (or an sk- pay-as-you-go key)'
    Write-Host '  3. Run this script again'
    Write-Host ''
    exit 1
}
$apiKey = $keyInfo.Key

$planInfo = Resolve-MiMoPlan -Key $apiKey -PlanChoice $Plan
$conflict = Get-MiMoKeyPlanConflict -Key $apiKey -BaseUrl $planInfo.BaseUrl
if ($conflict) {
    Write-Host ''
    Write-Host "ERROR: $conflict" -ForegroundColor Red
    Write-Host ''
    exit 1
}

$subcommands = @('attach', 'stop', 'kill', 'logs', 'rm', 'respawn', 'agents')
$first = if ($ClaudeArgs -and $ClaudeArgs.Count -gt 0) { $ClaudeArgs[0] } else { $null }
$isSubcommand = [bool]($first -and ($subcommands -contains $first.ToLowerInvariant()))

$default = Get-MiMoDefaultModel
$resolved = Resolve-LaunchModel `
    -Root $Root `
    -ProviderId 'mimo' `
    -Title 'Xiaomi MiMo - Model Selector' `
    -Catalog (Get-MiMoModelCatalog) `
    -Model $Model `
    -ModelWasBound:($PSBoundParameters.ContainsKey('Model')) `
    -SelectModel:$SelectModel `
    -SkipSelector:($isSubcommand -or $DryRun) `
    -BuiltInDefault $default.Model `
    -BuiltInFastDefault $default.FastModel
if (-not $resolved) {
    Write-Host 'Cancelled.' -ForegroundColor Yellow
    exit 0
}

$claudeEnv = Get-MiMoClaudeEnv -ApiKey $apiKey -BaseUrl $planInfo.BaseUrl `
    -MainModel $resolved.Model -FastModel $resolved.FastModel
$writeSettings = -not ($DryRun -or $NoSettingsWrite -or $isSubcommand)
$claudeCmd = Get-ClaudeCodeCommand

Write-Host ("Claude Code -> Xiaomi MiMo ({0})" -f (Get-MiMoPlanLabel -PlanId $planInfo.PlanId)) -ForegroundColor Cyan
Write-Host "  DETECT   : $($planInfo.Reason)" -ForegroundColor DarkGray
Write-Host "  KEY      : $(Format-MaskedSecret $apiKey)  from $($keyInfo.Source)" -ForegroundColor DarkGray
Write-Host "  BASE_URL : $($planInfo.BaseUrl)"
Write-Host "  MODEL    : $($resolved.Model)  (sonnet + opus slots)"
Write-Host "  FAST     : $($resolved.FastModel)  (haiku + subagent slots)"
Write-Host "  CWD      : $WorkingDirectory"
if ($ClaudeArgs) { Write-Host "  ARGS     : $($ClaudeArgs -join ' ')" }
Write-Host ("  SETTINGS : {0}" -f $(if ($writeSettings) { 'merge into ~/.claude/settings.json' } else { 'session env only' }))
Write-Host ("  CLAUDE   : {0}" -f $(if ($claudeCmd) { $claudeCmd.Source } else { 'not installed (will offer to install)' }))

if ($DryRun) {
    Write-Host ''
    Write-Host 'Dry run: nothing written, claude not started.' -ForegroundColor Yellow
    exit 0
}

if (-not (Confirm-ClaudeCodeInstalled -AutoInstall:$InstallClaude -NeverInstall:$SkipClaudeInstall)) {
    Write-Host ''
    Write-Host 'claude not started. Nothing was written.' -ForegroundColor Yellow
    exit 1
}

foreach ($name in $claudeEnv.Keys) {
    Set-Item -Path "Env:$name" -Value $claudeEnv[$name]
}

if ($writeSettings) {
    $loc = Get-ClaudeConfigLocation
    $backup = Set-ClaudeUserSettings -SettingsFile $loc.SettingsFile `
        -TopLevel (Get-MiMoClaudeTopLevelSetting) -Env $claudeEnv
    Set-ClaudeOnboardingComplete -Path $loc.OnboardingFile | Out-Null
    if ($backup) { Write-Host "  BACKUP   : $backup" -ForegroundColor DarkGray }
}
Write-Host '  Tip      : /status inside Claude Code should show the BASE_URL above'
Write-Host ''

$launch = if ($isSubcommand) { @($ClaudeArgs) } else { @('--model', $resolved.Model) + @($ClaudeArgs) }

Push-Location -LiteralPath $WorkingDirectory
try {
    & claude @launch
    $code = $LASTEXITCODE
}
finally {
    Pop-Location
}
exit $code
