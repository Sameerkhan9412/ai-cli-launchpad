BeforeDiscovery {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    $scripts = Get-ChildItem -Path (Join-Path $repoRoot 'launchers') -Recurse -Include '*.ps1', '*.psd1' |
        ForEach-Object { @{ Name = $_.FullName.Substring($repoRoot.Path.Length + 1); Path = $_.FullName } }
}

Describe 'Repository hygiene' {
    It '<Name> is ASCII-only (Windows PowerShell 5.1 reads BOM-less files as ANSI)' -ForEach $scripts {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }

    It '<Name> parses without errors' -ForEach $scripts {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'env.example contains only placeholder keys' {
        $example = Get-Content (Join-Path $PSScriptRoot '../launchers/claude-code/env.example') -Raw
        $example | Should -Match 'your_token_plan_key_here'
        $example | Should -Not -Match '(tp|sk)-[A-Za-z0-9]{24,}'
    }
}
