#Requires -Version 5.1
<#
.SYNOPSIS
  Provider-neutral helpers: .env parsing, BOM-free file writes, Claude Code user config.

.NOTES
  Dot-source from a launcher:  . (Join-Path $PSScriptRoot 'lib/Common.ps1')
  Works on Windows PowerShell 5.1 and PowerShell 7+ (Windows / macOS / Linux).
#>

function Write-Utf8NoBomFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )
    # Node's JSON.parse (Claude Code) rejects a UTF-8 BOM; PS 5.1 `-Encoding utf8` writes one.
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    [System.IO.File]::WriteAllText($full, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Import-DotEnvValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $i = $line.IndexOf('=')
        if ($i -lt 1) { continue }
        if ($line.Substring(0, $i).Trim() -ne $Name) { continue }
        $value = $line.Substring($i + 1).Trim().Trim('"').Trim("'")
        if ($value) { return $value }
        return $null
    }
    return $null
}

function Set-DotEnvValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value,
        [string[]]$RemoveName = @()
    )
    $lines = @()
    if (Test-Path -LiteralPath $Path) { $lines = @(Get-Content -LiteralPath $Path) }

    $out = New-Object System.Collections.Generic.List[string]
    $found = $false
    foreach ($line in $lines) {
        $key = $null
        if ($line -match '^\s*([^#=\s][^=]*?)\s*=') { $key = $Matches[1] }
        if ($key -eq $Name) {
            if (-not $found) { $out.Add("$Name=$Value"); $found = $true }
        }
        elseif ($key -and ($RemoveName -contains $key)) {
            continue
        }
        else {
            $out.Add($line)
        }
    }
    if (-not $found) {
        if ($out.Count -gt 0 -and $out[$out.Count - 1].Trim()) { $out.Add('') }
        $out.Add("$Name=$Value")
    }

    if ($PSCmdlet.ShouldProcess($Path, "Set $Name")) {
        Write-Utf8NoBomFile -Path $Path -Content (($out -join [Environment]::NewLine) + [Environment]::NewLine)
    }
}

function Format-MaskedSecret {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][string]$Value)
    if (-not $Value) { return '(empty)' }
    $v = $Value.Trim()
    if ($v.Length -le 10) { return ('*' * $v.Length) }
    return '{0}...{1}' -f $v.Substring(0, 5), $v.Substring($v.Length - 4)
}

function Get-ClaudeConfigLocation {
    <#
    .SYNOPSIS
      Where Claude Code keeps user config. Honors CLAUDE_CONFIG_DIR (then .claude.json lives inside it).
    #>
    [CmdletBinding()]
    param(
        [string]$HomeDirectory = $HOME,
        [string]$ConfigDir = $env:CLAUDE_CONFIG_DIR
    )
    if ($ConfigDir) {
        return [pscustomobject]@{
            ClaudeDir      = $ConfigDir
            SettingsFile   = Join-Path $ConfigDir 'settings.json'
            OnboardingFile = Join-Path $ConfigDir '.claude.json'
        }
    }
    $claudeDir = Join-Path $HomeDirectory '.claude'
    [pscustomobject]@{
        ClaudeDir      = $claudeDir
        SettingsFile   = Join-Path $claudeDir 'settings.json'
        OnboardingFile = Join-Path $HomeDirectory '.claude.json'
    }
}

function Backup-ConfigFile {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateRange(1, 100)][int]$Keep = 5
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $dir = Split-Path -Parent $Path
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [System.IO.Path]::GetExtension($Path)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $dest = Join-Path $dir ('{0}.backup-{1}{2}' -f $name, $stamp, $ext)
    Copy-Item -LiteralPath $Path -Destination $dest -Force

    Get-ChildItem -LiteralPath $dir -Filter ('{0}.backup-*{1}' -f $name, $ext) -File |
        Sort-Object Name -Descending |
        Select-Object -Skip $Keep |
        Remove-Item -Force
    return $dest
}

function ConvertTo-OrderedDictionary {
    [CmdletBinding()]
    param([object]$InputObject)
    $result = [ordered]@{}
    if ($null -eq $InputObject) { return $result }
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($k in $InputObject.Keys) { $result[$k] = $InputObject[$k] }
        return $result
    }
    foreach ($p in $InputObject.PSObject.Properties) { $result[$p.Name] = $p.Value }
    return $result
}

function Set-ClaudeUserSettings {
    <#
    .SYNOPSIS
      Merge provider settings into ~/.claude/settings.json.
    .DESCRIPTION
      Keeps every existing top-level key (permissions, hooks, statusLine, ...) and every
      existing env var; only overwrites the keys passed in. Backs up the old file first.
      Returns the backup path (or $null when there was no previous file).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$SettingsFile,
        [System.Collections.IDictionary]$TopLevel = @{},
        [System.Collections.IDictionary]$Env = @{}
    )
    $dir = Split-Path -Parent $SettingsFile
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $current = [ordered]@{}
    if (Test-Path -LiteralPath $SettingsFile) {
        $raw = Get-Content -LiteralPath $SettingsFile -Raw
        if ($raw -and $raw.Trim()) {
            try {
                $current = ConvertTo-OrderedDictionary ($raw | ConvertFrom-Json)
            }
            catch {
                Write-Warning "Existing $SettingsFile is not valid JSON; it will be backed up and replaced."
                $current = [ordered]@{}
            }
        }
    }

    foreach ($k in $TopLevel.Keys) { $current[$k] = $TopLevel[$k] }
    $mergedEnv = ConvertTo-OrderedDictionary $current['env']
    foreach ($k in $Env.Keys) { $mergedEnv[$k] = $Env[$k] }
    $current['env'] = $mergedEnv

    if (-not $PSCmdlet.ShouldProcess($SettingsFile, 'Merge Claude Code settings')) { return $null }
    $backup = Backup-ConfigFile -Path $SettingsFile
    Write-Utf8NoBomFile -Path $SettingsFile -Content ($current | ConvertTo-Json -Depth 20)
    return $backup
}

function Set-ClaudeOnboardingComplete {
    <#
    .SYNOPSIS
      Ensure ~/.claude.json has "hasCompletedOnboarding": true without touching anything else.
    .DESCRIPTION
      ~/.claude.json holds project trust, user-scope MCP servers and history. It is edited as
      text (never re-serialized) so nothing else in the file changes. Unknown shapes are left alone.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)

    $minimal = '{' + [Environment]::NewLine + '  "hasCompletedOnboarding": true' + [Environment]::NewLine + '}' + [Environment]::NewLine

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($PSCmdlet.ShouldProcess($Path, 'Create onboarding flag')) { Write-Utf8NoBomFile -Path $Path -Content $minimal }
        return 'created'
    }

    $text = Get-Content -LiteralPath $Path -Raw
    if (-not $text -or -not $text.Trim()) {
        if ($PSCmdlet.ShouldProcess($Path, 'Create onboarding flag')) { Write-Utf8NoBomFile -Path $Path -Content $minimal }
        return 'created'
    }
    if ($text -match '"hasCompletedOnboarding"\s*:\s*true') { return 'unchanged' }

    if ($text -match '"hasCompletedOnboarding"\s*:\s*false') {
        $new = [regex]::Replace($text, '"hasCompletedOnboarding"\s*:\s*false', '"hasCompletedOnboarding": true')
    }
    else {
        $trimmed = $text.Trim()
        if (-not $trimmed.StartsWith('{')) {
            Write-Warning "$Path is not a JSON object; onboarding flag not set."
            return 'skipped'
        }
        if ($trimmed -match '^\{\s*\}$') {
            $new = $minimal
        }
        else {
            $brace = $text.IndexOf('{')
            $new = $text.Substring(0, $brace + 1) + ' "hasCompletedOnboarding": true,' + $text.Substring($brace + 1)
        }
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Set hasCompletedOnboarding')) {
        Backup-ConfigFile -Path $Path | Out-Null
        Write-Utf8NoBomFile -Path $Path -Content $new
    }
    return 'updated'
}

function Test-IsWindowsHost {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    # $IsWindows does not exist on Windows PowerShell 5.1.
    return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

function Test-InteractiveSession {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    if (-not [Environment]::UserInteractive) { return $false }
    if ([Environment]::GetCommandLineArgs() | Where-Object { $_ -match '^-NonI' }) { return $false }
    try { return (-not [Console]::IsInputRedirected) } catch { return $true }
}

function Get-ClaudeCodeCommand {
    [CmdletBinding()]
    param()
    Get-Command claude -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Update-SessionPath {
    <#
    .SYNOPSIS
      Reload PATH so a CLI installed a moment ago (or in another terminal) is found without reopening the shell.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only changes PATH of the current session')]
    [CmdletBinding()]
    param([string[]]$ExtraDirectory)

    if (-not $PSBoundParameters.ContainsKey('ExtraDirectory')) {
        $ExtraDirectory = @([System.IO.Path]::Combine($HOME, '.local', 'bin'))
        if ($env:APPDATA) { $ExtraDirectory += [System.IO.Path]::Combine($env:APPDATA, 'npm') }
    }

    $sources = @($env:PATH)
    if (Test-IsWindowsHost) {
        $sources += [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $sources += [Environment]::GetEnvironmentVariable('Path', 'User')
    }
    $sources += @($ExtraDirectory | Where-Object { $_ -and (Test-Path -LiteralPath $_) })

    $sep = [System.IO.Path]::PathSeparator
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($source in $sources) {
        foreach ($entry in ("$source" -split [regex]::Escape($sep))) {
            if ($entry -and $seen.Add($entry.TrimEnd('\', '/'))) { $parts.Add($entry) }
        }
    }
    $env:PATH = $parts -join $sep
}

function Get-ClaudeInstallOption {
    <#
    .SYNOPSIS
      Ways to install Claude Code on this machine, recommended first.
    #>
    [CmdletBinding()]
    param(
        [bool]$OnWindows = (Test-IsWindowsHost),
        [bool]$HasNpm = [bool](Get-Command npm -CommandType Application -ErrorAction SilentlyContinue)
    )
    if ($OnWindows) {
        [pscustomobject]@{ Id = 'native-windows'; Label = 'Official installer (recommended)'; Command = 'irm https://claude.ai/install.ps1 | iex' }
    }
    else {
        [pscustomobject]@{ Id = 'native-unix'; Label = 'Official installer (recommended)'; Command = 'curl -fsSL https://claude.ai/install.sh | bash' }
    }
    if ($HasNpm) {
        [pscustomobject]@{ Id = 'npm'; Label = 'npm global package (needs Node 18+)'; Command = 'npm install -g @anthropic-ai/claude-code' }
    }
}

function Show-ClaudeInstallHelp {
    [CmdletBinding()]
    param([object[]]$Option = @(Get-ClaudeInstallOption))
    Write-Host 'Install Claude Code with one of these, open a NEW terminal, then run this script again:'
    foreach ($o in $Option) { Write-Host ('  {0}' -f $o.Command) }
    Write-Host '  Docs: https://docs.anthropic.com/en/docs/claude-code/setup'
}

function Install-ClaudeCode {
    <#
    .SYNOPSIS
      Run one install option, reload PATH, and report whether `claude` is now callable.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param([Parameter(Mandatory)][object]$Option)

    if (-not $PSCmdlet.ShouldProcess('Claude Code', $Option.Command)) { return $false }
    Write-Host ''
    Write-Host ("Installing Claude Code: {0}" -f $Option.Command) -ForegroundColor Cyan

    $code = 0
    try {
        switch ($Option.Id) {
            'native-windows' {
                $shell = (Get-Process -Id $PID).Path
                if (-not $shell -or $shell -notmatch '(powershell|pwsh)(\.exe)?$') { $shell = 'powershell' }
                # Child process: the official script runs isolated and TLS 1.2 is forced for Windows PowerShell 5.1.
                $script = '[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; irm https://claude.ai/install.ps1 | iex'
                & $shell -NoProfile -ExecutionPolicy Bypass -Command $script
                $code = $LASTEXITCODE
            }
            'native-unix' {
                & bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
                $code = $LASTEXITCODE
            }
            'npm' {
                $npm = Get-Command npm -CommandType Application -ErrorAction Stop | Select-Object -First 1
                & $npm.Source install -g '@anthropic-ai/claude-code'
                $code = $LASTEXITCODE
            }
            default { throw "Unknown install option '$($Option.Id)'." }
        }
    }
    catch {
        Write-Warning "Claude Code install failed: $($_.Exception.Message)"
        return $false
    }
    if ($code -and $code -ne 0) { Write-Warning "Installer exited with code $code." }

    Update-SessionPath
    return [bool](Get-ClaudeCodeCommand)
}

function Confirm-ClaudeCodeInstalled {
    <#
    .SYNOPSIS
      Make sure `claude` is callable; if it is missing, offer to install it and carry on.
    .DESCRIPTION
      Returns $true when claude is (now) available. Asks before installing unless -AutoInstall.
      Never prompts in a non-interactive session or with -NeverInstall; prints manual steps instead.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [switch]$AutoInstall,
        [switch]$NeverInstall
    )

    if (Get-ClaudeCodeCommand) { return $true }
    Update-SessionPath
    if (Get-ClaudeCodeCommand) { return $true }

    $options = @(Get-ClaudeInstallOption)
    Write-Host ''
    Write-Host 'Claude Code (the `claude` command) is not installed or not on PATH.' -ForegroundColor Yellow

    if ($NeverInstall -or (-not $AutoInstall -and -not (Test-InteractiveSession))) {
        Show-ClaudeInstallHelp -Option $options
        return $false
    }

    $choice = $options[0]
    if (-not $AutoInstall) {
        for ($i = 0; $i -lt $options.Count; $i++) {
            Write-Host ('  [{0}] {1,-38} {2}' -f ($i + 1), $options[$i].Label, $options[$i].Command)
        }
        Write-Host '  [0] No, do not install now'

        $picked = $null
        for ($try = 0; $try -lt 3 -and $null -eq $picked; $try++) {
            $answer = "$(Read-Host 'Install Claude Code now? [1]')".Trim().ToLowerInvariant()
            if ($answer -in @('', 'y', 'yes')) { $answer = '1' }
            if ($answer -in @('n', 'no', 'q')) { $answer = '0' }
            $n = 0
            if ([int]::TryParse($answer, [ref]$n) -and $n -ge 0 -and $n -le $options.Count) { $picked = $n }
            else { Write-Host ("Enter a number from 0 to {0}." -f $options.Count) -ForegroundColor Yellow }
        }
        if (-not $picked) {
            Write-Host 'Not installing Claude Code.' -ForegroundColor Yellow
            Show-ClaudeInstallHelp -Option $options
            return $false
        }
        $choice = $options[$picked - 1]
    }

    if (Install-ClaudeCode -Option $choice) {
        Write-Host ("Claude Code ready: {0}" -f (Get-ClaudeCodeCommand).Source) -ForegroundColor Green
        if ((Test-IsWindowsHost) -and -not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Host 'Note: Claude Code on Windows expects Git for Windows (https://git-scm.com/download/win).' -ForegroundColor Yellow
        }
        return $true
    }

    Write-Host ''
    Write-Host 'Claude Code is still not on PATH (the install failed or needs a new terminal).' -ForegroundColor Red
    Show-ClaudeInstallHelp -Option $options
    return $false
}
