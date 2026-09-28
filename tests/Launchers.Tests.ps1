BeforeAll {
    $source = Join-Path $PSScriptRoot '../launchers/claude-code'

    function New-LauncherCopy {
        $dest = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $dest | Out-Null
        Copy-Item (Join-Path $source '*.ps1') $dest
        Copy-Item (Join-Path $source 'lib') $dest -Recurse
        return $dest
    }

    function Invoke-Launcher {
        param([string]$Script, [hashtable]$Params = @{})
        $output = & $Script @Params 6>&1 2>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }

    $saved = @{}
    foreach ($k in 'MIMO_TOKEN_PLAN_API_KEY', 'MIMO_API_KEY', 'CLAUDE_CONFIG_DIR') {
        $saved[$k] = [Environment]::GetEnvironmentVariable($k)
    }
}

AfterAll {
    foreach ($k in $saved.Keys) {
        if ($saved[$k]) { Set-Item "Env:$k" $saved[$k] } else { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
    }
}

Describe 'Start-ClaudeWithMiMo.ps1 -DryRun' {
    BeforeEach {
        Remove-Item Env:MIMO_TOKEN_PLAN_API_KEY, Env:MIMO_API_KEY -ErrorAction SilentlyContinue
        $dir = New-LauncherCopy
        $launcher = Join-Path $dir 'Start-ClaudeWithMiMo.ps1'
    }

    It 'resolves a Token Plan key to the Singapore endpoint and the default model' {
        $env:MIMO_TOKEN_PLAN_API_KEY = 'tp-0123456789abcdef'
        $r = Invoke-Launcher $launcher @{ DryRun = $true }
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match 'token-plan-sgp\.xiaomimimo\.com/anthropic'
        $r.Output | Should -Match ([regex]::Escape('mimo-v2.6-pro[1m]'))
        $r.Output | Should -Match 'Dry run'
    }

    It 'never prints the full key' {
        $env:MIMO_TOKEN_PLAN_API_KEY = 'tp-0123456789abcdef'
        (Invoke-Launcher $launcher @{ DryRun = $true }).Output | Should -Not -Match '0123456789abcdef'
    }

    It 'reads the key from .env next to the script' {
        'MIMO_TOKEN_PLAN_API_KEY=sk-fromdotenvfile99' | Set-Content (Join-Path $dir '.env')
        $r = Invoke-Launcher $launcher @{ DryRun = $true }
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match 'api\.xiaomimimo\.com/anthropic'
    }

    It 'accepts a model alias' {
        $env:MIMO_TOKEN_PLAN_API_KEY = 'tp-0123456789abcdef'
        (Invoke-Launcher $launcher @{ DryRun = $true; Model = 'flash' }).Output | Should -Match 'MODEL\s+:\s+mimo-v2\.6-flash'
    }

    It 'refuses an sk- key on a Token Plan endpoint' {
        $env:MIMO_TOKEN_PLAN_API_KEY = 'sk-0123456789abcdef'
        $r = Invoke-Launcher $launcher @{ DryRun = $true; Plan = 'TokenPlanSgp' }
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match 'ERROR'
    }

    It 'explains how to add a key when none is found' {
        $r = Invoke-Launcher $launcher @{ DryRun = $true }
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match 'Missing MiMo API key'
    }

    It 'passes arguments after -- through to claude instead of binding them to launcher parameters' {
        $env:MIMO_TOKEN_PLAN_API_KEY = 'tp-0123456789abcdef'
        $output = & $launcher -DryRun -- --print 'hello world' 6>&1 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $output | Should -Match 'ARGS\s+:\s+--print hello world'
    }

    It 'reports a missing claude without offering to install during a dry run' {
        $env:MIMO_TOKEN_PLAN_API_KEY = 'tp-0123456789abcdef'
        $savedPath = $env:PATH
        try {
            $env:PATH = Join-Path $TestDrive 'empty-path'
            $r = Invoke-Launcher $launcher @{ DryRun = $true }
        }
        finally { $env:PATH = $savedPath }
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match 'CLAUDE\s+:\s+not installed'
        $r.Output | Should -Not -Match 'Install Claude Code now'
    }

    It 'shows where claude was found' {
        $env:MIMO_TOKEN_PLAN_API_KEY = 'tp-0123456789abcdef'
        $bin = Join-Path $TestDrive 'fake-bin'
        New-Item -ItemType Directory -Path $bin -Force | Out-Null
        $fake = if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'claude.cmd' } else { 'claude' }
        Set-Content -Path (Join-Path $bin $fake) -Value 'exit 0'
        if ($fake -eq 'claude') { chmod +x (Join-Path $bin $fake) }
        $savedPath = $env:PATH
        try {
            $env:PATH = $bin
            $r = Invoke-Launcher $launcher @{ DryRun = $true }
        }
        finally { $env:PATH = $savedPath }
        $r.Output | Should -Match ('CLAUDE\s+:\s+' + [regex]::Escape((Join-Path $bin $fake)))
    }

    It 'does not create preferences.json' {
        $env:MIMO_TOKEN_PLAN_API_KEY = 'tp-0123456789abcdef'
        Invoke-Launcher $launcher @{ DryRun = $true } | Out-Null
        Test-Path (Join-Path $dir 'preferences.json') | Should -BeFalse
    }
}

Describe 'Configure-ClaudeWithMiMo.ps1' {
    BeforeEach {
        Remove-Item Env:MIMO_TOKEN_PLAN_API_KEY, Env:MIMO_API_KEY -ErrorAction SilentlyContinue
        $dir = New-LauncherCopy
        $configure = Join-Path $dir 'Configure-ClaudeWithMiMo.ps1'
        $env:CLAUDE_CONFIG_DIR = Join-Path $TestDrive ([guid]::NewGuid())
    }
    AfterEach {
        Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
    }

    It 'writes settings.json, the onboarding flag and .env' {
        $r = Invoke-Launcher $configure @{ ApiKey = 'tp-0123456789abcdef'; Model = 'pro'; SkipClaudeInstall = $true }

        $settings = Get-Content (Join-Path $env:CLAUDE_CONFIG_DIR 'settings.json') -Raw | ConvertFrom-Json
        $settings.env.ANTHROPIC_BASE_URL | Should -Be 'https://token-plan-sgp.xiaomimimo.com/anthropic'
        $settings.env.ANTHROPIC_MODEL | Should -Be 'mimo-v2.6-pro'
        $settings.env.ANTHROPIC_DEFAULT_HAIKU_MODEL | Should -Be 'mimo-v2.6-flash'

        $onboarding = Get-Content (Join-Path $env:CLAUDE_CONFIG_DIR '.claude.json') -Raw | ConvertFrom-Json
        $onboarding.hasCompletedOnboarding | Should -BeTrue

        (Get-Content (Join-Path $dir '.env')) | Should -Contain 'MIMO_TOKEN_PLAN_API_KEY=tp-0123456789abcdef'
        $r.Output | Should -Not -Match '0123456789abcdef'
    }

    It 'keeps existing user settings' {
        New-Item -ItemType Directory -Path $env:CLAUDE_CONFIG_DIR | Out-Null
        '{"permissions":{"deny":["Read(.env)"]},"env":{"MY_VAR":"1"}}' |
            Set-Content (Join-Path $env:CLAUDE_CONFIG_DIR 'settings.json')

        Invoke-Launcher $configure @{ ApiKey = 'sk-0123456789abcdef'; SkipClaudeInstall = $true } | Out-Null

        $settings = Get-Content (Join-Path $env:CLAUDE_CONFIG_DIR 'settings.json') -Raw | ConvertFrom-Json
        $settings.permissions.deny | Should -Contain 'Read(.env)'
        $settings.env.MY_VAR | Should -Be '1'
        $settings.env.ANTHROPIC_BASE_URL | Should -Be 'https://api.xiaomimimo.com/anthropic'
    }
}
