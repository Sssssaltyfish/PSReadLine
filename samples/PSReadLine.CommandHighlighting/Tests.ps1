# Copyright (c) Microsoft Corporation.
# Licensed under the 2-Clause BSD License.

# Run in a fresh pwsh -NoProfile -NonInteractive process with the built PSReadLine imported.
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility
Import-Module (Join-Path $PSScriptRoot 'PSReadLine.CommandHighlighting.psd1') -Force

function Assert-Highlight($Text, $ExpectedColors) {
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
    $regions = (Get-PSReadLineOption).HighlightingHandler.Invoke($ast)
    $actual = @($regions | ForEach-Object Color)
    $expected = @($ExpectedColors | ForEach-Object { [Microsoft.PowerShell.HighlightRegion]::new(0, 1, $_).Color })
    if (($actual -join '|') -cne ($expected -join '|')) {
        throw "Unexpected highlights for '$Text': expected $($expected -join '|'), got $($actual -join '|')"
    }
    $previousEnd = 0
    foreach ($region in $regions) {
        if ($region.StartOffset -lt $previousEnd -or $region.EndOffset -gt $Text.Length) { throw 'Invalid region' }
        $previousEnd = $region.EndOffset
    }
}

$previous = [Func[System.Management.Automation.Language.Ast, Microsoft.PowerShell.HighlightRegion[]]] { param($ast) $null }
Set-PSReadLineOption -HighlightingHandler $previous
Push-Location $PSScriptRoot
try {
    Enable-CommandHighlighting
    Assert-Highlight 'Get-Date' @()
    Assert-Highlight '__psreadline_command_does_not_exist__' @("`e[31m")
    Assert-Highlight 'Get-Date | __psreadline_command_does_not_exist__' @("`e[31m")
    Assert-Highlight '& $dynamicName' @()
    Assert-Highlight '& "Get-Date"' @()
    Assert-Highlight 'Write-Output $(Get-Date)' @()
    Assert-Highlight '' @()
    Assert-Highlight 'Get-Date "unterminated' @()
    Assert-Highlight '.\Tests.ps1' @()
    Set-Location ..
    Assert-Highlight '.\Tests.ps1' @("`e[31m")
    Set-Location $PSScriptRoot
    Assert-Highlight '.\Tests.ps1' @()

    function global:Test-HighlightingCommand { throw 'Commands must not be executed' }
    Set-Alias -Name Test-HighlightingAlias -Value Test-HighlightingCommand -Scope Global
    Set-Alias -Name Test-HighlightingBrokenAlias -Value __psreadline_command_does_not_exist__ -Scope Global
    Assert-Highlight 'Test-HighlightingCommand' @()
    Assert-Highlight 'Test-HighlightingAlias' @()
    Assert-Highlight 'Test-HighlightingBrokenAlias' @("`e[31m")
    $pwshName = if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }
    Assert-Highlight "& '$PSHOME/$pwshName'" @()
    Remove-Item Function:/Test-HighlightingCommand
    Start-Sleep -Milliseconds 1100
    Assert-Highlight 'Test-HighlightingCommand' @("`e[31m")

    Remove-Module Microsoft.PowerShell.Archive -ErrorAction Ignore
    Assert-Highlight 'Compress-Archive' @("`e[31m")
    Set-Alias -Name Test-HighlightingModuleAlias -Value Compress-Archive -Scope Global
    Assert-Highlight 'Test-HighlightingModuleAlias' @("`e[31m")
    if (Get-Module Microsoft.PowerShell.Archive) { throw 'Highlighting imported a module' }

    Disable-CommandHighlighting
    if (-not [object]::ReferenceEquals((Get-PSReadLineOption).HighlightingHandler, $previous)) {
        throw 'Previous callback was not restored'
    }
    Enable-CommandHighlighting
    Set-PSReadLineOption -HighlightingHandler $previous
    Disable-CommandHighlighting
    if (-not [object]::ReferenceEquals((Get-PSReadLineOption).HighlightingHandler, $previous)) {
        throw 'A replacement callback was overwritten'
    }
    Enable-CommandHighlighting
    Remove-Module PSReadLine.CommandHighlighting
    if (-not [object]::ReferenceEquals((Get-PSReadLineOption).HighlightingHandler, $previous)) {
        throw 'Module removal did not restore the previous callback'
    }
    'Command highlighting tests passed.'
} finally {
    Pop-Location
    Remove-Item Function:/Test-HighlightingCommand -ErrorAction Ignore
    Remove-Item Alias:/Test-HighlightingAlias, Alias:/Test-HighlightingBrokenAlias, Alias:/Test-HighlightingModuleAlias -ErrorAction Ignore
    Remove-Module PSReadLine.CommandHighlighting -ErrorAction Ignore
    Set-PSReadLineOption -HighlightingHandler $null
}
