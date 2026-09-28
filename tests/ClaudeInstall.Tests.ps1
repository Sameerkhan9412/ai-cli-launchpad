BeforeAll {
    . (Join-Path $PSScriptRoot '../launchers/claude-code/lib/Common.ps1')

    $script:nativeOption = [pscustomobject]@{ Id = 'native-windows'; Label = 'Official installer'; Command = 'irm x | iex' }
    $script:npmOption = [pscustomobject]@{ Id = 'npm'; Label = 'npm'; Command = 'npm install -g x' }
}

Describe 'Get-ClaudeInstallOption' {
    It 'offers the Windows installer first and npm only when npm exists' {
        $options = @(Get-ClaudeInstallOption -OnWindows $true -HasNpm $true)
        $options.Id | Should -Be @('native-windows', 'npm')
        $options[0].Command | Should -Match 'install\.ps1'
    }

    It 'offers the shell installer on macOS / Linux' {
        $options = @(Get-ClaudeInstallOption -OnWindows $false -HasNpm $false)
        $options.Count | Should -Be 1
        $options[0].Id | Should -Be 'native-unix'
        $options[0].Command | Should -Match 'install\.sh'
    }
}

Describe 'Update-SessionPath' {
    BeforeEach { $savedPath = $env:PATH }
    AfterEach { $env:PATH = $savedPath }

    It 'adds an existing extra folder once and keeps current entries' {
        $bin = Join-Path $TestDrive 'bin'
        New-Item -ItemType Directory -Path $bin -Force | Out-Null
        $sep = [System.IO.Path]::PathSeparator
        $env:PATH = "$bin$sep$savedPath"

        Update-SessionPath -ExtraDirectory $bin, (Join-Path $TestDrive 'missing')

        $entries = $env:PATH -split [regex]::Escape($sep)
        @($entries | Where-Object { $_ -eq $bin }).Count | Should -Be 1
        $entries | Should -Not -Contain (Join-Path $TestDrive 'missing')
    }
}

Describe 'Install-ClaudeCode' {
    BeforeAll { Mock Write-Host {} }

    It 'does nothing under -WhatIf' {
        Mock Update-SessionPath {}
        Install-ClaudeCode -Option $script:nativeOption -WhatIf | Should -BeFalse
        Should -Invoke Update-SessionPath -Times 0
    }

    It 'reports failure for an unknown option' {
        Mock Write-Warning {}
        Install-ClaudeCode -Option ([pscustomobject]@{ Id = 'bogus'; Command = 'x' }) | Should -BeFalse
    }
}

Describe 'Confirm-ClaudeCodeInstalled' {
    BeforeAll {
        Mock Write-Host {}
        Mock Update-SessionPath {}
        Mock Get-ClaudeInstallOption { $script:nativeOption; $script:npmOption }
    }

    Context 'claude is already installed' {
        It 'returns true without asking' {
            Mock Get-ClaudeCodeCommand { [pscustomobject]@{ Source = 'C:\tools\claude.exe' } }
            Mock Read-Host { 'n' }
            Confirm-ClaudeCodeInstalled | Should -BeTrue
            Should -Invoke Read-Host -Times 0
        }
    }

    Context 'claude is missing' {
        BeforeEach {
            Mock Get-ClaudeCodeCommand { $null }
            Mock Test-InteractiveSession { $true }
            Mock Install-ClaudeCode { $true }
        }

        It 'installs with the recommended option when the user presses Enter' {
            Mock Read-Host { '' }
            Confirm-ClaudeCodeInstalled | Should -BeTrue
            Should -Invoke Install-ClaudeCode -Times 1 -ParameterFilter { $Option.Id -eq 'native-windows' }
        }

        It 'installs with the option number the user picks' {
            Mock Read-Host { '2' }
            Confirm-ClaudeCodeInstalled | Should -BeTrue
            Should -Invoke Install-ClaudeCode -Times 1 -ParameterFilter { $Option.Id -eq 'npm' }
        }

        It 'does not install when the user answers <Answer>' -ForEach @(
            @{ Answer = '0' }
            @{ Answer = 'n' }
            @{ Answer = 'No' }
        ) {
            Mock Read-Host { $Answer }
            Confirm-ClaudeCodeInstalled | Should -BeFalse
            Should -Invoke Install-ClaudeCode -Times 0
        }

        It 'gives up after three invalid answers' {
            Mock Read-Host { 'maybe' }
            Confirm-ClaudeCodeInstalled | Should -BeFalse
            Should -Invoke Read-Host -Times 3 -Exactly
            Should -Invoke Install-ClaudeCode -Times 0
        }

        It 'returns false when the install does not put claude on PATH' {
            Mock Read-Host { 'y' }
            Mock Install-ClaudeCode { $false }
            Confirm-ClaudeCodeInstalled | Should -BeFalse
        }

        It 'installs without asking under -AutoInstall' {
            Mock Read-Host { '0' }
            Confirm-ClaudeCodeInstalled -AutoInstall | Should -BeTrue
            Should -Invoke Read-Host -Times 0
            Should -Invoke Install-ClaudeCode -Times 1
        }

        It 'never asks or installs under -NeverInstall' {
            Mock Read-Host { 'y' }
            Confirm-ClaudeCodeInstalled -NeverInstall | Should -BeFalse
            Should -Invoke Read-Host -Times 0
            Should -Invoke Install-ClaudeCode -Times 0
        }

        It 'never asks in a non-interactive session' {
            Mock Test-InteractiveSession { $false }
            Mock Read-Host { 'y' }
            Confirm-ClaudeCodeInstalled | Should -BeFalse
            Should -Invoke Read-Host -Times 0
            Should -Invoke Install-ClaudeCode -Times 0
        }
    }
}
