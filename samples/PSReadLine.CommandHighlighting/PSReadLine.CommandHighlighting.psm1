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
    $context = $ExecutionContext

    $script:handler = [Func[System.Management.Automation.Language.Ast, Microsoft.PowerShell.HighlightRegion[]]] {
        param($ast)

        # Reuse lookups only within this render. The next render observes the
        # current session and filesystem without timers or invalidation hooks.
        $commandsFound = [Collections.Generic.Dictionary[string, bool]]::new([StringComparer]::Ordinal)
        $commands = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }, $true)

        foreach ($command in $commands) {
            $name = $command.GetCommandName()
            if ([string]::IsNullOrEmpty($name)) { continue }

            if (-not $commandsFound.ContainsKey($name)) {
                # Enumerate exact matches without the module auto-loading performed by GetCommand.
                $resolved = [Linq.Enumerable]::FirstOrDefault[System.Management.Automation.CommandInfo](
                    $context.InvokeCommand.GetCommands($name, [System.Management.Automation.CommandTypes]::All, $false))
                if ($resolved -is [System.Management.Automation.AliasInfo]) {
                    $resolved = $resolved.ResolvedCommand
                }
                $commandsFound[$name] = $null -ne $resolved
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
