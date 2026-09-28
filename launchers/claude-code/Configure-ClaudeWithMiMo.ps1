#Requires -Version 5.1
<#
.SYNOPSIS
  One-time setup: point Claude Code at Xiaomi MiMo in ~/.claude/settings.json.

.DESCRIPTION
  After this, plain `claude` (from any folder or IDE terminal) uses MiMo.
  Existing settings are merged, not replaced, and backed up first.
  ~/.claude.json only gets "hasCompletedOnboarding": true so the Anthropic login screen is skipped.

  Key lookup: -ApiKey > env MIMO_TOKEN_PLAN_API_KEY > .env > env/.env MIMO_API_KEY > hidden prompt.
  A key passed with -ApiKey or typed at the prompt is saved to .env for Start-ClaudeWithMiMo.ps1.
  Finally checks that Claude Code is installed and offers to install it if it is missing.

.PARAMETER ApiKey
  MiMo key (tp-... Token Plan or sk-... pay-as-you-go). Prefer .env over typing it here
  (command-line values end up in shell history).

.PARAMETER Plan
  Force an endpoint instead of detecting it from the key prefix.

.PARAMETER Model
  Main model id or alias. Default: mimo-v2.6-pro[1m] (fast slot: mimo-v2.6-flash).

.PARAMETER InstallClaude
  If Claude Code is missing, install it with the recommended method without asking.

.PARAMETER SkipClaudeInstall
  Do not check for or offer to install Claude Code.

.EXAMPLE
  .\Configure-ClaudeWithMiMo.ps1

.EXAMPLE
  .\Configure-ClaudeWithMiMo.ps1 -Plan TokenPlanAms -Model flash

.EXAMPLE
  .\Configure-ClaudeWithMiMo.ps1 -InstallClaude      # new machine: configure and install in one go
#>
[CmdletBinding()]
param(
    [string]$ApiKey,
    [ValidateSet('Auto', 'PayAsYouGo', 'TokenPlanSgp', 'TokenPlanCn', 'TokenPlanAms')]
    [string]$Plan = 'Auto',
    [string]$Model,
    [switch]$InstallClaude,
    [switch]$SkipClaudeInstall
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$EnvFile = Join-Path $Root '.env'

. (Join-Path $Root 'lib/Common.ps1')
. (Join-Path $Root 'lib/MiMo.ps1')
. (Join-Path $Root 'lib/ModelSelector.ps1')

$keyInfo = Resolve-MiMoApiKey -ApiKey $ApiKey -EnvFile $EnvFile
if (-not $keyInfo) {
    Write-Host -NoNewline 'Enter your Xiaomi MiMo API key (input hidden): '
    $secure = Read-Host -AsSecureString
    $typed = (New-Object System.Net.NetworkCredential('', $secure)).Password
    if ($typed) { $keyInfo = [pscustomobject]@{ Key = $typed.Trim(); Source = 'prompt' } }
}
if (-not $keyInfo -or -not $keyInfo.Key) {
    Write-Host 'ERROR: MiMo API key cannot be empty.' -ForegroundColor Red
    exit 1
}
$apiKey = $keyInfo.Key

$planInfo = Resolve-MiMoPlan -Key $apiKey -PlanChoice $Plan
$conflict = Get-MiMoKeyPlanConflict -Key $apiKey -BaseUrl $planInfo.BaseUrl
if ($conflict) {
    Write-Host "ERROR: $conflict" -ForegroundColor Red
    exit 1
}

$default = Get-MiMoDefaultModel
$mainModel = $default.Model
$fastModel = $default.FastModel
if ($Model) {
    $entry = Resolve-CatalogEntry -Catalog (Get-MiMoModelCatalog) -Token $Model
    if ($entry) {
        $mainModel = $entry.Id
        $fastModel = $entry.FastModel
    }
    else {
        $mainModel = $Model.Trim()
    }
}

$loc = Get-ClaudeConfigLocation
$claudeEnv = Get-MiMoClaudeEnv -ApiKey $apiKey -BaseUrl $planInfo.BaseUrl -MainModel $mainModel -FastModel $fastModel
$backup = Set-ClaudeUserSettings -SettingsFile $loc.SettingsFile -TopLevel (Get-MiMoClaudeTopLevelSetting) -Env $claudeEnv
$onboarding = Set-ClaudeOnboardingComplete -Path $loc.OnboardingFile

$savedToEnv = $false
if ($keyInfo.Source -in @('parameter', 'prompt') -or (Test-Path -LiteralPath $EnvFile)) {
    Set-DotEnvValue -Path $EnvFile -Name 'MIMO_TOKEN_PLAN_API_KEY' -Value $apiKey -RemoveName 'MIMO_API_KEY'
    $savedToEnv = $true
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Claude Code configured for Xiaomi MiMo'
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host (' Plan        : {0}' -f (Get-MiMoPlanLabel -PlanId $planInfo.PlanId))
Write-Host (' Endpoint    : {0}' -f $planInfo.BaseUrl)
Write-Host (' Key         : {0}  from {1}' -f (Format-MaskedSecret $apiKey), $keyInfo.Source)
Write-Host (' Main model  : {0}  (sonnet + opus)' -f $mainModel)
Write-Host (' Fast model  : {0}  (haiku + subagents)' -f $fastModel)
Write-Host  ' Prompt cache: 1 hour (main + subagents)'
Write-Host (' Settings    : {0}' -f $loc.SettingsFile)
if ($backup) { Write-Host (' Backup      : {0}' -f $backup) -ForegroundColor DarkGray }
Write-Host (' Onboarding  : {0} ({1})' -f $loc.OnboardingFile, $onboarding)
if ($savedToEnv) { Write-Host (' .env        : key saved to {0}' -f $EnvFile) }

if (-not $SkipClaudeInstall) {
    if (Confirm-ClaudeCodeInstalled -AutoInstall:$InstallClaude) {
        Write-Host (' Claude Code : {0}' -f (Get-ClaudeCodeCommand).Source)
    }
    else {
        Write-Host ''
        Write-Host 'MiMo settings are saved; they apply as soon as Claude Code is installed.' -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host 'Close any running Claude Code, open a NEW terminal, then:'
Write-Host ''
Write-Host ("  cd `"{0}`"" -f $Root)
Write-Host '  .\Start-ClaudeWithMiMo.ps1      # or just: claude'
Write-Host ''
Write-Host 'Inside Claude Code: /status (Base URL) then /context'
Write-Host ''
