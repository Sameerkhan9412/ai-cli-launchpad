BeforeAll {
    . (Join-Path $PSScriptRoot '../launchers/claude-code/lib/Common.ps1')
}

Describe 'Import-DotEnvValue' {
    BeforeAll {
        $envFile = Join-Path $TestDrive 'sample.env'
        @(
            '# comment line'
            ''
            'PLAIN=abc'
            'QUOTED="tp-123"'
            "SINGLE='sk-456'"
            '  SPACED  =  value with spaces  '
            'WITH_EQUALS=a=b=c'
            'EMPTY='
            '# COMMENTED=nope'
        ) | Set-Content -Path $envFile
    }

    It 'returns <Expected> for <Name>' -ForEach @(
        @{ Name = 'PLAIN'; Expected = 'abc' }
        @{ Name = 'QUOTED'; Expected = 'tp-123' }
        @{ Name = 'SINGLE'; Expected = 'sk-456' }
        @{ Name = 'SPACED'; Expected = 'value with spaces' }
        @{ Name = 'WITH_EQUALS'; Expected = 'a=b=c' }
    ) {
        Import-DotEnvValue -Path $envFile -Name $Name | Should -Be $Expected
    }

    It 'returns $null for empty, commented or missing keys' {
        Import-DotEnvValue -Path $envFile -Name 'EMPTY' | Should -BeNullOrEmpty
        Import-DotEnvValue -Path $envFile -Name 'COMMENTED' | Should -BeNullOrEmpty
        Import-DotEnvValue -Path $envFile -Name 'NOPE' | Should -BeNullOrEmpty
    }

    It 'returns $null when the file does not exist' {
        Import-DotEnvValue -Path (Join-Path $TestDrive 'missing.env') -Name 'PLAIN' | Should -BeNullOrEmpty
    }
}

Describe 'Set-DotEnvValue' {
    It 'replaces an existing key and keeps other lines' {
        $f = Join-Path $TestDrive 'replace.env'
        "# keys`nA=1`nKEY=old`nB=2" | Set-Content -Path $f -NoNewline
        Set-DotEnvValue -Path $f -Name 'KEY' -Value 'new'
        $lines = Get-Content $f
        $lines | Should -Contain 'KEY=new'
        $lines | Should -Contain 'A=1'
        $lines | Should -Contain '# keys'
        $lines | Should -Not -Contain 'KEY=old'
    }

    It 'appends when the key is missing' {
        $f = Join-Path $TestDrive 'append.env'
        'A=1' | Set-Content -Path $f
        Set-DotEnvValue -Path $f -Name 'KEY' -Value 'v'
        Import-DotEnvValue -Path $f -Name 'KEY' | Should -Be 'v'
    }

    It 'creates the file when missing' {
        $f = Join-Path $TestDrive 'new.env'
        Set-DotEnvValue -Path $f -Name 'KEY' -Value 'v'
        Import-DotEnvValue -Path $f -Name 'KEY' | Should -Be 'v'
    }

    It 'drops legacy names passed in -RemoveName' {
        $f = Join-Path $TestDrive 'legacy.env'
        "OLD=x`nKEY=y" | Set-Content -Path $f
        Set-DotEnvValue -Path $f -Name 'KEY' -Value 'z' -RemoveName 'OLD'
        Import-DotEnvValue -Path $f -Name 'OLD' | Should -BeNullOrEmpty
        Import-DotEnvValue -Path $f -Name 'KEY' | Should -Be 'z'
    }

    It 'writes without a UTF-8 BOM' {
        $f = Join-Path $TestDrive 'bom.env'
        Set-DotEnvValue -Path $f -Name 'KEY' -Value 'v'
        $bytes = [System.IO.File]::ReadAllBytes($f)
        $bytes[0] | Should -Not -Be 0xEF
    }
}

Describe 'Format-MaskedSecret' {
    It 'keeps only prefix and suffix of long keys' {
        Format-MaskedSecret 'tp-abcdefghijklmnop1234' | Should -Be 'tp-ab...1234'
    }
    It 'fully masks short values' {
        Format-MaskedSecret 'short' | Should -Be '*****'
    }
    It 'handles empty input' {
        Format-MaskedSecret '' | Should -Be '(empty)'
    }
}

Describe 'Get-ClaudeConfigLocation' {
    It 'uses the home directory by default' {
        $loc = Get-ClaudeConfigLocation -HomeDirectory $TestDrive -ConfigDir ''
        $loc.SettingsFile | Should -Be (Join-Path (Join-Path $TestDrive '.claude') 'settings.json')
        $loc.OnboardingFile | Should -Be (Join-Path $TestDrive '.claude.json')
    }
    It 'honors CLAUDE_CONFIG_DIR' {
        $dir = Join-Path $TestDrive 'custom'
        $loc = Get-ClaudeConfigLocation -HomeDirectory $TestDrive -ConfigDir $dir
        $loc.SettingsFile | Should -Be (Join-Path $dir 'settings.json')
        $loc.OnboardingFile | Should -Be (Join-Path $dir '.claude.json')
    }
}

Describe 'Backup-ConfigFile' {
    It 'returns $null when there is nothing to back up' {
        Backup-ConfigFile -Path (Join-Path $TestDrive 'none.json') | Should -BeNullOrEmpty
    }
    It 'keeps only the newest N backups' {
        $dir = Join-Path $TestDrive 'backups'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $f = Join-Path $dir 'settings.json'
        '{}' | Set-Content $f
        1..4 | ForEach-Object { "old$_" | Set-Content (Join-Path $dir "settings.backup-2020010$_-000000.json") }
        $dest = Backup-ConfigFile -Path $f -Keep 2
        Test-Path $dest | Should -BeTrue
        @(Get-ChildItem $dir -Filter 'settings.backup-*.json').Count | Should -Be 2
    }
}

Describe 'Set-ClaudeUserSettings' {
    BeforeEach {
        $dir = Join-Path $TestDrive ([guid]::NewGuid())
        $settings = Join-Path $dir 'settings.json'
    }

    It 'creates the folder and file when missing' {
        Set-ClaudeUserSettings -SettingsFile $settings -TopLevel @{ a = 1 } -Env @{ X = 'y' } | Should -BeNullOrEmpty
        $json = Get-Content $settings -Raw | ConvertFrom-Json
        $json.a | Should -Be 1
        $json.env.X | Should -Be 'y'
    }

    It 'keeps unrelated keys and env vars, overwrites managed ones, and backs up' {
        New-Item -ItemType Directory -Path $dir | Out-Null
        @'
{ "permissions": { "allow": ["Bash(git status)"] },
  "statusLine": { "type": "command", "command": "echo hi" },
  "env": { "MY_VAR": "keep", "ANTHROPIC_BASE_URL": "https://old" } }
'@ | Set-Content $settings

        $backup = Set-ClaudeUserSettings -SettingsFile $settings `
            -TopLevel ([ordered]@{ promptCacheTtl = '1h' }) `
            -Env ([ordered]@{ ANTHROPIC_BASE_URL = 'https://new' })

        $json = Get-Content $settings -Raw | ConvertFrom-Json
        $json.permissions.allow | Should -Contain 'Bash(git status)'
        $json.statusLine.command | Should -Be 'echo hi'
        $json.env.MY_VAR | Should -Be 'keep'
        $json.env.ANTHROPIC_BASE_URL | Should -Be 'https://new'
        $json.promptCacheTtl | Should -Be '1h'
        Test-Path $backup | Should -BeTrue
    }

    It 'replaces an invalid JSON file instead of failing' {
        New-Item -ItemType Directory -Path $dir | Out-Null
        'not json {' | Set-Content $settings
        Set-ClaudeUserSettings -SettingsFile $settings -Env @{ X = 'y' } -WarningAction SilentlyContinue | Out-Null
        (Get-Content $settings -Raw | ConvertFrom-Json).env.X | Should -Be 'y'
    }

    It 'writes without a UTF-8 BOM' {
        Set-ClaudeUserSettings -SettingsFile $settings -Env @{ X = 'y' } | Out-Null
        [System.IO.File]::ReadAllBytes($settings)[0] | Should -Be ([byte][char]'{')
    }
}

Describe 'Set-ClaudeOnboardingComplete' {
    BeforeEach {
        $f = Join-Path $TestDrive ("{0}.claude.json" -f [guid]::NewGuid())
    }

    It 'creates a minimal file when missing' {
        Set-ClaudeOnboardingComplete -Path $f | Should -Be 'created'
        (Get-Content $f -Raw | ConvertFrom-Json).hasCompletedOnboarding | Should -BeTrue
    }

    It 'leaves a file that already has the flag untouched' {
        $original = '{"hasCompletedOnboarding":true,"projects":{"C:/x":{"allowedTools":[]}}}'
        [System.IO.File]::WriteAllText($f, $original)
        Set-ClaudeOnboardingComplete -Path $f | Should -Be 'unchanged'
        [System.IO.File]::ReadAllText($f) | Should -BeExactly $original
    }

    It 'flips false to true' {
        [System.IO.File]::WriteAllText($f, '{"numStartups":3,"hasCompletedOnboarding": false}')
        Set-ClaudeOnboardingComplete -Path $f | Should -Be 'updated'
        $json = Get-Content $f -Raw | ConvertFrom-Json
        $json.hasCompletedOnboarding | Should -BeTrue
        $json.numStartups | Should -Be 3
    }

    It 'adds the flag and keeps every other key (projects, mcpServers)' {
        [System.IO.File]::WriteAllText($f, '{"mcpServers":{"fs":{"command":"npx"}},"projects":{"a":{"x":1}}}')
        Set-ClaudeOnboardingComplete -Path $f | Should -Be 'updated'
        $json = Get-Content $f -Raw | ConvertFrom-Json
        $json.hasCompletedOnboarding | Should -BeTrue
        $json.mcpServers.fs.command | Should -Be 'npx'
        $json.projects.a.x | Should -Be 1
    }

    It 'skips files that are not a JSON object' {
        [System.IO.File]::WriteAllText($f, '[1,2,3]')
        Set-ClaudeOnboardingComplete -Path $f -WarningAction SilentlyContinue | Should -Be 'skipped'
        [System.IO.File]::ReadAllText($f) | Should -BeExactly '[1,2,3]'
    }
}
