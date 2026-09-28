#Requires -Version 5.1
<#
.SYNOPSIS
  Xiaomi MiMo provider profile for Claude Code: endpoints, key detection, model catalog, env.

.NOTES
  Anthropic-compatible endpoints documented by Xiaomi MiMo:
    Pay-as-you-go  (sk- keys)      https://api.xiaomimimo.com/anthropic
    Token Plan     (tp- / ttp-)    https://token-plan-{sgp|cn|ams}.xiaomimimo.com/anthropic
#>

function Get-MiMoEndpoint {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('PayAsYouGo', 'TokenPlanSgp', 'TokenPlanCn', 'TokenPlanAms')]
        [string]$PlanId
    )
    switch ($PlanId) {
        'PayAsYouGo' { 'https://api.xiaomimimo.com/anthropic' }
        'TokenPlanSgp' { 'https://token-plan-sgp.xiaomimimo.com/anthropic' }
        'TokenPlanCn' { 'https://token-plan-cn.xiaomimimo.com/anthropic' }
        'TokenPlanAms' { 'https://token-plan-ams.xiaomimimo.com/anthropic' }
    }
}

function Get-MiMoPlanLabel {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$PlanId)
    switch ($PlanId) {
        'PayAsYouGo' { 'Pay-as-you-go' }
        'TokenPlanSgp' { 'Token Plan Singapore' }
        'TokenPlanCn' { 'Token Plan China' }
        'TokenPlanAms' { 'Token Plan Europe (AMS)' }
        default { $PlanId }
    }
}

function Resolve-MiMoPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,
        [ValidateSet('Auto', 'PayAsYouGo', 'TokenPlanSgp', 'TokenPlanCn', 'TokenPlanAms')]
        [string]$PlanChoice = 'Auto'
    )
    if ($PlanChoice -ne 'Auto') {
        return [pscustomobject]@{
            PlanId  = $PlanChoice
            BaseUrl = Get-MiMoEndpoint -PlanId $PlanChoice
            Reason  = "forced via -Plan $PlanChoice"
        }
    }
    $k = $Key.Trim().ToLowerInvariant()
    if ($k.StartsWith('tp-') -or $k.StartsWith('ttp-')) {
        return [pscustomobject]@{
            PlanId  = 'TokenPlanSgp'
            BaseUrl = Get-MiMoEndpoint -PlanId 'TokenPlanSgp'
            Reason  = 'key prefix tp-/ttp- -> Token Plan Singapore'
        }
    }
    if ($k.StartsWith('sk-')) {
        return [pscustomobject]@{
            PlanId  = 'PayAsYouGo'
            BaseUrl = Get-MiMoEndpoint -PlanId 'PayAsYouGo'
            Reason  = 'key prefix sk- -> pay-as-you-go'
        }
    }
    return [pscustomobject]@{
        PlanId  = 'TokenPlanSgp'
        BaseUrl = Get-MiMoEndpoint -PlanId 'TokenPlanSgp'
        Reason  = 'unknown key prefix; defaulting to Token Plan Singapore (override with -Plan)'
    }
}

function Get-MiMoKeyPlanConflict {
    <#
    .SYNOPSIS
      Returns an error message when the key type cannot work with the Base URL, else $null.
      Mixing them fails later with an unhelpful 400 "token unavailable" / 401.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$BaseUrl
    )
    $k = $Key.Trim().ToLowerInvariant()
    if ($k.StartsWith('sk-') -and $BaseUrl -like '*token-plan*') {
        return 'sk- (pay-as-you-go) key cannot use a Token Plan Base URL. Use -Plan PayAsYouGo or a tp- key.'
    }
    if (($k.StartsWith('tp-') -or $k.StartsWith('ttp-')) -and $BaseUrl -like '*api.xiaomimimo.com*') {
        return 'tp- (Token Plan) key cannot use the pay-as-you-go Base URL. Use -Plan TokenPlanSgp/Cn/Ams or an sk- key.'
    }
    return $null
}

function Resolve-MiMoApiKey {
    <#
    .SYNOPSIS
      Find the MiMo key. Order: -ApiKey, env MIMO_TOKEN_PLAN_API_KEY, .env MIMO_TOKEN_PLAN_API_KEY,
      env MIMO_API_KEY, .env MIMO_API_KEY. Returns @{ Key; Source } or $null.
    #>
    [CmdletBinding()]
    param(
        [string]$ApiKey,
        [string]$EnvFile
    )
    if ($ApiKey) { return [pscustomobject]@{ Key = $ApiKey.Trim(); Source = 'parameter' } }

    foreach ($name in @('MIMO_TOKEN_PLAN_API_KEY', 'MIMO_API_KEY')) {
        $fromEnv = [Environment]::GetEnvironmentVariable($name)
        if ($fromEnv) { return [pscustomobject]@{ Key = $fromEnv.Trim(); Source = "environment ($name)" } }
        if ($EnvFile) {
            $fromFile = Import-DotEnvValue -Path $EnvFile -Name $name
            if ($fromFile) { return [pscustomobject]@{ Key = $fromFile; Source = ".env ($name)" } }
        }
    }
    return $null
}

function Get-MiMoModelCatalog {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    @(
        [pscustomobject]@{
            Id = 'mimo-v2.6-pro[1m]'; Label = 'v2.6 Pro + 1M context (recommended)'; Group = 'MiMo v2.6'
            FastModel = 'mimo-v2.6-flash'; Aliases = @('pro1m', 'pro-1m', '1m')
        }
        [pscustomobject]@{
            Id = 'mimo-v2.6-pro'; Label = 'v2.6 Pro (standard context)'; Group = 'MiMo v2.6'
            FastModel = 'mimo-v2.6-flash'; Aliases = @('pro', 'v2.6-pro')
        }
        [pscustomobject]@{
            Id = 'mimo-v2.6-flash'; Label = 'v2.6 Flash (fast / cheap)'; Group = 'MiMo v2.6'
            FastModel = 'mimo-v2.6-flash'; Aliases = @('flash', 'v2.6-flash')
        }
        [pscustomobject]@{
            Id = 'mimo-v2.5-pro[1m]'; Label = 'v2.5 Pro + 1M (legacy, retires 2026-10-21)'; Group = 'MiMo v2.5 (legacy)'
            FastModel = 'mimo-v2.5'; Aliases = @('v2.5-pro-1m')
        }
        [pscustomobject]@{
            Id = 'mimo-v2.5-pro'; Label = 'v2.5 Pro (legacy)'; Group = 'MiMo v2.5 (legacy)'
            FastModel = 'mimo-v2.5'; Aliases = @('v2.5-pro')
        }
        [pscustomobject]@{
            Id = 'mimo-v2.5'; Label = 'v2.5 (legacy fast)'; Group = 'MiMo v2.5 (legacy)'
            FastModel = 'mimo-v2.5'; Aliases = @('v2.5')
        }
    )
}

function Get-MiMoDefaultModel {
    [CmdletBinding()]
    param()
    [pscustomobject]@{ Model = 'mimo-v2.6-pro[1m]'; FastModel = 'mimo-v2.6-flash' }
}

function Get-MiMoClaudeEnv {
    <#
    .SYNOPSIS
      Env vars that point Claude Code at MiMo. Main model fills the Sonnet/Opus slots,
      fast model fills Haiku / background / subagent slots. 1h prompt cache on.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)][string]$ApiKey,
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$MainModel,
        [Parameter(Mandatory)][string]$FastModel
    )
    [ordered]@{
        ANTHROPIC_BASE_URL                    = $BaseUrl
        ANTHROPIC_AUTH_TOKEN                  = $ApiKey
        ANTHROPIC_API_KEY                     = ''
        ANTHROPIC_MODEL                       = $MainModel
        ANTHROPIC_DEFAULT_SONNET_MODEL        = $MainModel
        ANTHROPIC_DEFAULT_OPUS_MODEL          = $MainModel
        ANTHROPIC_DEFAULT_HAIKU_MODEL         = $FastModel
        ANTHROPIC_SMALL_FAST_MODEL            = $FastModel
        CLAUDE_CODE_SUBAGENT_MODEL            = $FastModel
        ENABLE_PROMPT_CACHING_1H              = '1'
        CLAUDE_CODE_PROMPT_CACHE_TTL          = '1h'
        CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL = '1h'
    }
}

function Get-MiMoClaudeTopLevelSetting {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()
    [ordered]@{
        promptCacheTtl         = '1h'
        subagentPromptCacheTtl = '1h'
        includeGitInstructions = $false
    }
}
