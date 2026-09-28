BeforeAll {
    $lib = Join-Path $PSScriptRoot '../launchers/claude-code/lib'
    . (Join-Path $lib 'Common.ps1')
    . (Join-Path $lib 'ModelSelector.ps1')

    $catalog = @(
        [pscustomobject]@{ Id = 'model-a'; Label = 'A'; Group = 'G'; FastModel = 'model-a-fast'; Aliases = @('a') }
        [pscustomobject]@{ Id = 'model-b'; Label = 'B'; Group = 'G'; FastModel = $null; Aliases = @() }
    )
}

Describe 'Resolve-CatalogEntry' {
    It 'matches by 1-based menu number' {
        (Resolve-CatalogEntry -Catalog $catalog -Token '2').Id | Should -Be 'model-b'
    }
    It 'matches id and alias case-insensitively' {
        (Resolve-CatalogEntry -Catalog $catalog -Token 'MODEL-A').Id | Should -Be 'model-a'
        (Resolve-CatalogEntry -Catalog $catalog -Token ' A ').Id | Should -Be 'model-a'
    }
    It 'returns $null for <Token>' -ForEach @(
        @{ Token = '0' }, @{ Token = '99' }, @{ Token = 'nope' }, @{ Token = '' }, @{ Token = '   ' }
    ) {
        Resolve-CatalogEntry -Catalog $catalog -Token $Token | Should -BeNullOrEmpty
    }
}

Describe 'Provider preferences' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $root | Out-Null
    }

    It 'returns $null before anything is saved' {
        Get-ProviderPreference -Root $root -ProviderId 'mimo' | Should -BeNullOrEmpty
    }

    It 'round-trips a saved default per provider' {
        Set-ProviderPreference -Root $root -ProviderId 'mimo' -Model 'm1' -FastModel 'f1'
        Set-ProviderPreference -Root $root -ProviderId 'other' -Model 'm2' -FastModel 'f2'
        $p = Get-ProviderPreference -Root $root -ProviderId 'mimo'
        $p.Model | Should -Be 'm1'
        $p.FastModel | Should -Be 'f1'
        (Get-ProviderPreference -Root $root -ProviderId 'other').Model | Should -Be 'm2'
    }

    It 'overwrites an existing provider entry' {
        Set-ProviderPreference -Root $root -ProviderId 'mimo' -Model 'm1' -FastModel 'f1'
        Set-ProviderPreference -Root $root -ProviderId 'mimo' -Model 'm3' -FastModel 'f3'
        (Get-ProviderPreference -Root $root -ProviderId 'mimo').Model | Should -Be 'm3'
    }

    It 'ignores a corrupt preferences file' {
        'not json' | Set-Content (Join-Path $root 'preferences.json')
        Get-ProviderPreference -Root $root -ProviderId 'mimo' | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-LaunchModel (non-interactive paths)' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $root | Out-Null
        $common = @{
            Root = $root; ProviderId = 'p'; Catalog = $catalog
            BuiltInDefault = 'model-a'; BuiltInFastDefault = 'model-a-fast'
        }
    }

    It 'uses the built-in default when nothing is saved' {
        $r = Resolve-LaunchModel @common -SkipSelector
        $r.Model | Should -Be 'model-a'
        $r.FastModel | Should -Be 'model-a-fast'
    }

    It 'prefers the saved default over the built-in one' {
        Set-ProviderPreference -Root $root -ProviderId 'p' -Model 'model-b' -FastModel 'model-b'
        (Resolve-LaunchModel @common -SkipSelector).Model | Should -Be 'model-b'
    }

    It 'resolves a bound alias to its id and fast model' {
        $r = Resolve-LaunchModel @common -Model 'a' -ModelWasBound $true -SkipSelector
        $r.Model | Should -Be 'model-a'
        $r.FastModel | Should -Be 'model-a-fast'
    }

    It 'passes through an unknown bound model id with the fallback fast model' {
        $r = Resolve-LaunchModel @common -Model 'custom-x' -ModelWasBound $true -SkipSelector
        $r.Model | Should -Be 'custom-x'
        $r.FastModel | Should -Be 'model-a-fast'
    }

    It 'does not write preferences in SkipSelector mode' {
        Resolve-LaunchModel @common -Model 'a' -ModelWasBound $true -SkipSelector | Out-Null
        Test-Path (Join-Path $root 'preferences.json') | Should -BeFalse
    }
}
