BeforeAll {
    $lib = Join-Path $PSScriptRoot '../launchers/claude-code/lib'
    . (Join-Path $lib 'Common.ps1')
    . (Join-Path $lib 'MiMo.ps1')
    . (Join-Path $lib 'ModelSelector.ps1')
}

Describe 'Resolve-MiMoPlan' {
    It 'maps <Key> to <PlanId>' -ForEach @(
        @{ Key = 'tp-abc'; PlanId = 'TokenPlanSgp' }
        @{ Key = 'TTP-team'; PlanId = 'TokenPlanSgp' }
        @{ Key = '  sk-abc  '; PlanId = 'PayAsYouGo' }
        @{ Key = 'weird-key'; PlanId = 'TokenPlanSgp' }
    ) {
        (Resolve-MiMoPlan -Key $Key).PlanId | Should -Be $PlanId
    }

    It 'uses the pay-as-you-go endpoint for sk- keys' {
        (Resolve-MiMoPlan -Key 'sk-1').BaseUrl | Should -Be 'https://api.xiaomimimo.com/anthropic'
    }

    It 'honors a forced plan' {
        $r = Resolve-MiMoPlan -Key 'tp-1' -PlanChoice 'TokenPlanAms'
        $r.PlanId | Should -Be 'TokenPlanAms'
        $r.BaseUrl | Should -Be 'https://token-plan-ams.xiaomimimo.com/anthropic'
        $r.Reason | Should -Match 'forced'
    }

    It 'explains unknown prefixes' {
        (Resolve-MiMoPlan -Key 'xyz').Reason | Should -Match 'unknown'
    }
}

Describe 'Get-MiMoKeyPlanConflict' {
    It 'blocks sk- keys on Token Plan URLs' {
        Get-MiMoKeyPlanConflict -Key 'sk-1' -BaseUrl (Get-MiMoEndpoint 'TokenPlanCn') | Should -Match 'sk-'
    }
    It 'blocks tp- keys on the pay-as-you-go URL' {
        Get-MiMoKeyPlanConflict -Key 'tp-1' -BaseUrl (Get-MiMoEndpoint 'PayAsYouGo') | Should -Match 'tp-'
    }
    It 'allows matching combinations' -ForEach @(
        @{ Key = 'sk-1'; Plan = 'PayAsYouGo' }
        @{ Key = 'tp-1'; Plan = 'TokenPlanSgp' }
        @{ Key = 'ttp-1'; Plan = 'TokenPlanAms' }
    ) {
        Get-MiMoKeyPlanConflict -Key $Key -BaseUrl (Get-MiMoEndpoint $Plan) | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-MiMoApiKey' {
    BeforeAll {
        $saved = @{
            MIMO_TOKEN_PLAN_API_KEY = $env:MIMO_TOKEN_PLAN_API_KEY
            MIMO_API_KEY            = $env:MIMO_API_KEY
        }
    }
    BeforeEach {
        Remove-Item Env:MIMO_TOKEN_PLAN_API_KEY, Env:MIMO_API_KEY -ErrorAction SilentlyContinue
        $envFile = Join-Path $TestDrive 'keys.env'
        Remove-Item $envFile -ErrorAction SilentlyContinue
    }
    AfterAll {
        foreach ($k in $saved.Keys) {
            if ($saved[$k]) { Set-Item "Env:$k" $saved[$k] } else { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
        }
    }

    It 'prefers the explicit parameter' {
        $env:MIMO_TOKEN_PLAN_API_KEY = 'tp-env'
        $r = Resolve-MiMoApiKey -ApiKey 'tp-param' -EnvFile $envFile
        $r.Key | Should -Be 'tp-param'
        $r.Source | Should -Be 'parameter'
    }

    It 'prefers the environment over .env' {
        'MIMO_TOKEN_PLAN_API_KEY=tp-file' | Set-Content $envFile
        $env:MIMO_TOKEN_PLAN_API_KEY = 'tp-env'
        (Resolve-MiMoApiKey -EnvFile $envFile).Key | Should -Be 'tp-env'
    }

    It 'reads .env when the environment is empty' {
        'MIMO_TOKEN_PLAN_API_KEY=tp-file' | Set-Content $envFile
        $r = Resolve-MiMoApiKey -EnvFile $envFile
        $r.Key | Should -Be 'tp-file'
        $r.Source | Should -Match '\.env'
    }

    It 'falls back to the legacy MIMO_API_KEY name' {
        'MIMO_API_KEY=sk-legacy' | Set-Content $envFile
        (Resolve-MiMoApiKey -EnvFile $envFile).Key | Should -Be 'sk-legacy'
    }

    It 'returns $null when no key exists anywhere' {
        Resolve-MiMoApiKey -EnvFile $envFile | Should -BeNullOrEmpty
    }
}

Describe 'MiMo model catalog' {
    BeforeAll { $catalog = Get-MiMoModelCatalog }

    It 'has unique ids' {
        $ids = $catalog | ForEach-Object Id
        ($ids | Select-Object -Unique).Count | Should -Be $ids.Count
    }

    It 'has unique aliases across models' {
        $aliases = $catalog | ForEach-Object { $_.Aliases }
        ($aliases | Select-Object -Unique).Count | Should -Be $aliases.Count
    }

    It 'contains the default model' {
        $catalog.Id | Should -Contain (Get-MiMoDefaultModel).Model
    }

    It 'resolves alias <Alias> to <Id>' -ForEach @(
        @{ Alias = 'pro1m'; Id = 'mimo-v2.6-pro[1m]' }
        @{ Alias = 'PRO'; Id = 'mimo-v2.6-pro' }
        @{ Alias = 'flash'; Id = 'mimo-v2.6-flash' }
    ) {
        (Resolve-CatalogEntry -Catalog $catalog -Token $Alias).Id | Should -Be $Id
    }
}

Describe 'Get-MiMoClaudeEnv' {
    It 'fills main and fast model slots and clears ANTHROPIC_API_KEY' {
        $e = Get-MiMoClaudeEnv -ApiKey 'tp-1' -BaseUrl 'https://u' -MainModel 'main' -FastModel 'fast'
        $e.ANTHROPIC_BASE_URL | Should -Be 'https://u'
        $e.ANTHROPIC_AUTH_TOKEN | Should -Be 'tp-1'
        $e.ANTHROPIC_API_KEY | Should -Be ''
        $e.ANTHROPIC_DEFAULT_SONNET_MODEL | Should -Be 'main'
        $e.ANTHROPIC_DEFAULT_OPUS_MODEL | Should -Be 'main'
        $e.ANTHROPIC_DEFAULT_HAIKU_MODEL | Should -Be 'fast'
        $e.CLAUDE_CODE_SUBAGENT_MODEL | Should -Be 'fast'
    }
}
