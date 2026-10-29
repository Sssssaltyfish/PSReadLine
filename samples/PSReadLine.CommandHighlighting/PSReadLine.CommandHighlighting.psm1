# Copyright (c) Microsoft Corporation.
# Licensed under the 2-Clause BSD License.

$script:handler = $null
$script:previousHandler = $null

function Enable-CommandHighlighting {
    [CmdletBinding()]
    param(
        [string] $InvalidColor = "`e[31m"
    )

    if (-not (Get-Command Set-PSReadLineOption).Parameters.ContainsKey('HighlightingHandler')) {
        throw 'This module requires PSReadLine with the HighlightingHandler option.'
    }

    # Validate the color before replacing the current handler.
    $invalid = [Microsoft.PowerShell.HighlightRegion]::new(0, 1, $InvalidColor).Color
    Disable-CommandHighlighting
    $script:previousHandler = (Get-PSReadLineOption).HighlightingHandler
    $state = @{
        Cache = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        Path = $null
        Location = $null
    }
    $context = $ExecutionContext

    $script:handler = [Func[System.Management.Automation.Language.Ast, Microsoft.PowerShell.HighlightRegion[]]] {
        param($ast)

        $location = $context.SessionState.Path.CurrentLocation.Path
        if ($state.Path -cne $env:PATH -or $state.Location -cne $location) {
            $state.Cache.Clear()
            $state.Path = $env:PATH
            $state.Location = $location
        }

        $now = [Environment]::TickCount64
        $commands = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }, $true)

        foreach ($command in $commands) {
            $name = $command.GetCommandName()
            if ([string]::IsNullOrEmpty($name)) { continue }

            $entry = $state.Cache[$name]
            if ($null -eq $entry -or $now - $entry.Time -ge 1000) {
                # Enumerate exact matches without the module auto-loading performed by GetCommand.
                $resolved = @($context.InvokeCommand.GetCommands($name, [System.Management.Automation.CommandTypes]::All, $false))[0]
                if ($resolved -is [System.Management.Automation.AliasInfo]) {
                    $resolved = $resolved.ResolvedCommand
                }
                $entry = @{ Exists = $null -ne $resolved; Time = $now }
                if ($state.Cache.Count -ge 256) { $state.Cache.Clear() }
                $state.Cache[$name] = $entry
            }

            if (-not $entry.Exists) {
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
