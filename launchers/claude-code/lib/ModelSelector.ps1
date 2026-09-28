#Requires -Version 5.1
<#
.SYNOPSIS
  Shared model picker + saved default per provider.

.NOTES
  Saved defaults live in preferences.json next to the launcher (gitignored).
  A launcher defines its catalog (Id, Label, Group, FastModel, Aliases) and calls Resolve-LaunchModel.
  Dot-source Common.ps1 first (uses Write-Utf8NoBomFile).
#>

function Get-ClaudePreferencesPath {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Root)
    return (Join-Path $Root 'preferences.json')
}

function Get-ProviderPreference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ProviderId
    )
    $path = Get-ClaudePreferencesPath -Root $Root
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $all = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        return $null
    }
    $node = $all.$ProviderId
    if (-not $node -or -not $node.model) { return $null }
    return [pscustomobject]@{
        Model     = [string]$node.model
        FastModel = if ($node.fastModel) { [string]$node.fastModel } else { [string]$node.model }
        ChosenAt  = if ($node.chosenAt) { [string]$node.chosenAt } else { $null }
    }
}

function Set-ProviderPreference {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ProviderId,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$FastModel
    )
    $path = Get-ClaudePreferencesPath -Root $Root
    $all = $null
    if (Test-Path -LiteralPath $path) {
        try { $all = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
        catch { $all = $null }
    }
    if (-not $all) { $all = [pscustomobject]@{} }

    $entry = [pscustomobject]@{
        model     = $Model
        fastModel = $FastModel
        chosenAt  = (Get-Date).ToString('o')
    }
    $all | Add-Member -NotePropertyName $ProviderId -NotePropertyValue $entry -Force

    if ($PSCmdlet.ShouldProcess($path, "Save default model for $ProviderId")) {
        Write-Utf8NoBomFile -Path $path -Content ($all | ConvertTo-Json -Depth 5)
    }
}

function Resolve-CatalogEntry {
    <#
    .SYNOPSIS
      Match a menu number (1-based), model id or alias (case-insensitive). $null when no match.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Catalog,
        [AllowEmptyString()][string]$Token
    )
    if ([string]::IsNullOrWhiteSpace($Token)) { return $null }
    $t = $Token.Trim()

    $num = 0
    if ([int]::TryParse($t, [ref]$num)) {
        if ($num -ge 1 -and $num -le $Catalog.Count) { return $Catalog[$num - 1] }
        return $null
    }

    $lower = $t.ToLowerInvariant()
    foreach ($m in $Catalog) {
        if ($m.Id.ToLowerInvariant() -eq $lower) { return $m }
        foreach ($a in @($m.Aliases)) {
            if ($a -and ([string]$a).ToLowerInvariant() -eq $lower) { return $m }
        }
    }
    return $null
}

function Show-ModelCatalogMenu {
    [CmdletBinding()]
    param(
        [string]$Title,
        [object[]]$Catalog,
        [string]$SavedModel
    )
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host " $Title"
    Write-Host '============================================================' -ForegroundColor Cyan
    if ($SavedModel) {
        Write-Host (' Saved default: {0}  (Enter = use it)' -f $SavedModel) -ForegroundColor Green
    }
    else {
        Write-Host ' First run: pick a default model (saved for next launches)' -ForegroundColor Yellow
    }
    Write-Host ''

    $lastGroup = $null
    $i = 0
    foreach ($m in $Catalog) {
        $i++
        if ($m.Group -ne $lastGroup) {
            $lastGroup = $m.Group
            Write-Host (' --- {0} ---' -f $m.Group) -ForegroundColor DarkCyan
        }
        $mark = if ($SavedModel -and $m.Id -eq $SavedModel) { ' *' } else { '' }
        Write-Host ('  [{0}] {1,-28} {2}{3}' -f $i, $m.Id, $m.Label, $mark)
    }

    Write-Host ''
    Write-Host '  [c] Custom model id'
    Write-Host '  [0] Cancel'
    Write-Host '============================================================' -ForegroundColor Cyan
    if ($SavedModel) { Write-Host -NoNewline "Select model [Enter=$SavedModel]: " }
    else { Write-Host -NoNewline 'Select model [number]: ' }
    return (Read-Host)
}

function Select-FromCatalog {
    [CmdletBinding()]
    param(
        [string]$Title,
        [object[]]$Catalog,
        [string]$SavedModel,
        [string]$SavedFast,
        [string]$DefaultFastFallback
    )
    while ($true) {
        $choice = Show-ModelCatalogMenu -Title $Title -Catalog $Catalog -SavedModel $SavedModel
        if ([string]::IsNullOrWhiteSpace($choice)) {
            if ($SavedModel) {
                return [pscustomobject]@{
                    Model     = $SavedModel
                    FastModel = if ($SavedFast) { $SavedFast } else { $SavedModel }
                    Save      = $false
                }
            }
            Write-Host 'Pick a number (first run has no default yet).' -ForegroundColor Yellow
            continue
        }

        $trimmed = $choice.Trim()
        if ($trimmed -eq '0') { return $null }

        if ($trimmed.ToLowerInvariant() -eq 'c') {
            Write-Host -NoNewline 'Custom model id: '
            $custom = Read-Host
            if ([string]::IsNullOrWhiteSpace($custom)) {
                Write-Host 'Empty id - try again.' -ForegroundColor Yellow
                continue
            }
            $fast = if ($DefaultFastFallback) { $DefaultFastFallback } else { $custom.Trim() }
            Write-Host -NoNewline 'Save as default for next runs? [Y/n]: '
            $saveAns = Read-Host
            return [pscustomobject]@{
                Model     = $custom.Trim()
                FastModel = $fast
                Save      = (-not $saveAns) -or ($saveAns.Trim().ToLowerInvariant() -ne 'n')
            }
        }

        $entry = Resolve-CatalogEntry -Catalog $Catalog -Token $trimmed
        if (-not $entry) {
            Write-Host "Invalid choice: $trimmed" -ForegroundColor Yellow
            continue
        }

        $fast = if ($entry.FastModel) { $entry.FastModel } else { $entry.Id }
        $doSave = -not $SavedModel
        if ($SavedModel -and $entry.Id -ne $SavedModel) {
            Write-Host -NoNewline ("Save '{0}' as new default? [Y/n]: " -f $entry.Id)
            $saveAns = Read-Host
            $doSave = (-not $saveAns) -or ($saveAns.Trim().ToLowerInvariant() -ne 'n')
        }
        return [pscustomobject]@{ Model = $entry.Id; FastModel = $fast; Save = $doSave }
    }
}

function Resolve-LaunchModel {
    <#
    .SYNOPSIS
      Decide which model to launch with. Returns @{ Model; FastModel }, or $null if the user cancels.

    .PARAMETER ModelWasBound
      True when the caller passed -Model on the command line.

    .PARAMETER SelectModel
      Force the interactive menu.

    .PARAMETER SkipSelector
      No prompts at all: bound model > saved default > built-in default (CI, dry runs, subcommands).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ProviderId,
        [string]$Title,
        [Parameter(Mandatory)][object[]]$Catalog,
        [string]$Model,
        [bool]$ModelWasBound = $false,
        [switch]$SelectModel,
        [switch]$SkipSelector,
        [Parameter(Mandatory)][string]$BuiltInDefault,
        [string]$BuiltInFastDefault
    )

    $pref = Get-ProviderPreference -Root $Root -ProviderId $ProviderId
    $savedModel = if ($pref) { $pref.Model } else { $null }
    $savedFast = if ($pref) { $pref.FastModel } else { $null }
    $fallbackFast = if ($BuiltInFastDefault) { $BuiltInFastDefault } else { $BuiltInDefault }

    if ($ModelWasBound -and -not [string]::IsNullOrWhiteSpace($Model)) {
        $entry = Resolve-CatalogEntry -Catalog $Catalog -Token $Model
        $resolved = if ($entry) { $entry.Id } else { $Model.Trim() }
        $fast = if ($entry -and $entry.FastModel) { $entry.FastModel } else { $fallbackFast }
        if (-not $SkipSelector) {
            Write-Host (' Model override: {0}' -f $resolved) -ForegroundColor DarkGray
            if ($savedModel -ne $resolved) {
                Write-Host -NoNewline ' Save as default for next runs? [y/N]: '
                $saveAns = Read-Host
                if ($saveAns -and $saveAns.Trim().ToLowerInvariant() -eq 'y') {
                    Set-ProviderPreference -Root $Root -ProviderId $ProviderId -Model $resolved -FastModel $fast
                    Write-Host ' Saved default.' -ForegroundColor Green
                }
            }
        }
        return [pscustomobject]@{ Model = $resolved; FastModel = $fast }
    }

    if ($SkipSelector) {
        $m = if ($savedModel) { $savedModel } else { $BuiltInDefault }
        $f = if ($savedFast) { $savedFast } else { $fallbackFast }
        return [pscustomobject]@{ Model = $m; FastModel = $f }
    }

    if ($SelectModel -or -not $savedModel) {
        $pick = Select-FromCatalog -Title $Title -Catalog $Catalog `
            -SavedModel $savedModel -SavedFast $savedFast -DefaultFastFallback $fallbackFast
        if (-not $pick) { return $null }
        if ($pick.Save -or -not $savedModel) {
            Set-ProviderPreference -Root $Root -ProviderId $ProviderId -Model $pick.Model -FastModel $pick.FastModel
            Write-Host (' Saved default: {0} (fast/haiku: {1})' -f $pick.Model, $pick.FastModel) -ForegroundColor Green
        }
        return [pscustomobject]@{ Model = $pick.Model; FastModel = $pick.FastModel }
    }

    Write-Host ''
    Write-Host (' Saved model: {0}  (fast/haiku: {1})' -f $savedModel, $savedFast) -ForegroundColor Cyan
    Write-Host -NoNewline ' [Enter] use default   [m] change model: '
    $ans = Read-Host
    if ($ans -and $ans.Trim().ToLowerInvariant() -eq 'm') {
        $pick = Select-FromCatalog -Title $Title -Catalog $Catalog `
            -SavedModel $savedModel -SavedFast $savedFast -DefaultFastFallback $fallbackFast
        if (-not $pick) {
            Write-Host 'Keeping saved default.' -ForegroundColor DarkGray
            return [pscustomobject]@{ Model = $savedModel; FastModel = $savedFast }
        }
        if ($pick.Save) {
            Set-ProviderPreference -Root $Root -ProviderId $ProviderId -Model $pick.Model -FastModel $pick.FastModel
            Write-Host (' Saved default: {0}' -f $pick.Model) -ForegroundColor Green
        }
        return [pscustomobject]@{ Model = $pick.Model; FastModel = $pick.FastModel }
    }

    return [pscustomobject]@{ Model = $savedModel; FastModel = $savedFast }
}
