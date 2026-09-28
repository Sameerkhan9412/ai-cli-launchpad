@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Interactive CLI: coloured console output is the product, not a side effect.
        'PSAvoidUsingWriteHost'
        # Names like Set-ClaudeUserSettings mirror the file they edit (settings.json).
        'PSUseSingularNouns'
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.4')
        }
    }
}
