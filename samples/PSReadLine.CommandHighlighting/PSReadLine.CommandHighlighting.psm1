# Copyright (c) Microsoft Corporation.
# Licensed under the 2-Clause BSD License.

$script:handler = $null
$script:previousHandler = $null

function Enable-CommandHighlighting {
    [CmdletBinding()]
    param(
        [string] $InvalidColor = "`e[31m",
        [ValidateRange(0, 60000)]
        [int] $CacheDurationMilliseconds = 1000
    )

    if (-not (Get-Command Set-PSReadLineOption).Parameters.ContainsKey('HighlightingHandler')) {
        throw 'This module requires PSReadLine with the HighlightingHandler option.'
    }

    # Validate the color before replacing the current handler.
    $invalid = [Microsoft.PowerShell.HighlightRegion]::new(0, 1, $InvalidColor).Color
    Disable-CommandHighlighting
    $script:previousHandler = (Get-PSReadLineOption).HighlightingHandler
    $context = $ExecutionContext
    $state = @{
        Cache = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        Path = $null
        PathExt = $null
        Location = $null
    }

    $script:handler = [Func[System.Management.Automation.Language.Ast, Microsoft.PowerShell.HighlightRegion[]]] {
        param($ast)

        $location = $context.SessionState.Path.CurrentLocation.Path
        if ($state.Path -cne $env:PATH -or $state.PathExt -cne $env:PATHEXT -or $state.Location -cne $location) {
            $state.Cache.Clear()
            $state.Path = $env:PATH
            $state.PathExt = $env:PATHEXT
            $state.Location = $location
        }
        $now = [Environment]::TickCount64
        # Deduplicate even when the cross-render cache is disabled or fills up.
        $commandsFound = [Collections.Generic.Dictionary[string, bool]]::new([StringComparer]::Ordinal)
        $commands = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }, $true)

        foreach ($command in $commands) {
            $name = $command.GetCommandName()
            if ([string]::IsNullOrEmpty($name)) { continue }

            if (-not $commandsFound.ContainsKey($name)) {
                $entry = $state.Cache[$name]
                if ($CacheDurationMilliseconds -gt 0 -and $null -ne $entry -and
                    $now - $entry.Time -lt $CacheDurationMilliseconds) {
                    $commandsFound[$name] = $entry.Exists
                }
                else {
                    # Enumerate exact matches without the module auto-loading performed by GetCommand.
                    $resolved = [Linq.Enumerable]::FirstOrDefault[System.Management.Automation.CommandInfo](
                        $context.InvokeCommand.GetCommands($name, [System.Management.Automation.CommandTypes]::All, $false))
                    if ($resolved -is [System.Management.Automation.AliasInfo]) {
                        $resolved = $resolved.ResolvedCommand
                    }
                    $commandsFound[$name] = $null -ne $resolved
                    if ($CacheDurationMilliseconds -gt 0) {
                        if ($state.Cache.Count -ge 256) { $state.Cache.Clear() }
                        $state.Cache[$name] = @{ Exists = $commandsFound[$name]; Time = [Environment]::TickCount64 }
                    }
                }
            }

            if (-not $commandsFound[$name]) {
                $extent = $command.CommandElements[0].Extent
                [Microsoft.PowerShell.HighlightRegion]::new($extent.StartOffset, $extent.EndOffset, $invalid)
            }
        }
    }.GetNewClosure()

    Set-PSReadLineOption -HighlightingHandler $script:handler
}

function Disable-CommandHighlighting {
    [CmdletBinding()]
    param()

    if ($null -ne $script:handler) {
        if ([object]::ReferenceEquals((Get-PSReadLineOption).HighlightingHandler, $script:handler)) {
            Set-PSReadLineOption -HighlightingHandler $script:previousHandler
        }
        $script:handler = $null
        $script:previousHandler = $null
    }
}

$ExecutionContext.SessionState.Module.OnRemove = { Disable-CommandHighlighting }
Export-ModuleMember -Function Enable-CommandHighlighting, Disable-CommandHighlighting
