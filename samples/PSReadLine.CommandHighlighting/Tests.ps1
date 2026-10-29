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
    Enable-CommandHighlighting -CacheDurationMilliseconds 0
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

    Assert-Highlight 'Test-HighlightingCommand' @("`e[31m")
    function global:Test-HighlightingCommand { throw 'Commands must not be executed' }
    Set-Alias -Name Test-HighlightingAlias -Value Test-HighlightingCommand -Scope Global
    Set-Alias -Name Test-HighlightingBrokenAlias -Value __psreadline_command_does_not_exist__ -Scope Global
    Assert-Highlight 'Test-HighlightingCommand' @()
    Assert-Highlight 'Test-HighlightingAlias' @()
    Assert-Highlight 'Test-HighlightingBrokenAlias' @("`e[31m")
    $pwshName = if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }
    Assert-Highlight "& '$PSHOME/$pwshName'" @()
    Remove-Item Function:/Test-HighlightingCommand
    Assert-Highlight 'Test-HighlightingCommand' @("`e[31m")
    Assert-Highlight 'Test-HighlightingAlias' @("`e[31m")
    Set-Alias -Name Test-HighlightingAlias -Value Get-Date -Scope Global
    Assert-Highlight 'Test-HighlightingAlias' @()
    Set-Alias -Name Test-HighlightingAlias -Value __psreadline_command_does_not_exist__ -Scope Global
    Assert-Highlight 'Test-HighlightingAlias' @("`e[31m")
    Assert-Highlight '__psreadline_command_does_not_exist__; __psreadline_command_does_not_exist__' @("`e[31m", "`e[31m")

    $testDirectory = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    $testScript = Join-Path $testDirectory 'Test-PSReadLineHighlightFile.ps1'
    $originalPath = $env:PATH
    New-Item -ItemType Directory -Path $testDirectory | Out-Null
    try {
        Assert-Highlight "& '$testScript'" @("`e[31m")
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Tests.ps1') -Destination $testScript
        Assert-Highlight "& '$testScript'" @()
        Assert-Highlight 'Test-PSReadLineHighlightFile.ps1' @("`e[31m")
        $env:PATH = $testDirectory + [IO.Path]::PathSeparator + $originalPath
        Assert-Highlight 'Test-PSReadLineHighlightFile.ps1' @()
        $env:PATH = $originalPath
        Assert-Highlight 'Test-PSReadLineHighlightFile.ps1' @("`e[31m")
        Remove-Item -LiteralPath $testScript
        Assert-Highlight "& '$testScript'" @("`e[31m")
    } finally {
        $env:PATH = $originalPath
        Remove-Item -LiteralPath $testScript -ErrorAction Ignore
        Remove-Item -LiteralPath $testDirectory
    }

    Remove-Module Microsoft.PowerShell.Archive -ErrorAction Ignore
    Assert-Highlight 'Compress-Archive' @("`e[31m")
    Set-Alias -Name Test-HighlightingModuleAlias -Value Compress-Archive -Scope Global
    Assert-Highlight 'Test-HighlightingModuleAlias' @("`e[31m")
    if (Get-Module Microsoft.PowerShell.Archive) { throw 'Highlighting imported a module' }

    Enable-CommandHighlighting -InvalidColor '#e06c75' -CacheDurationMilliseconds 0
    Assert-Highlight 'Get-Date' @()
    Assert-Highlight '__psreadline_command_does_not_exist__' @('#e06c75')
    Enable-CommandHighlighting -InvalidColor DarkYellow
    Assert-Highlight '__psreadline_command_does_not_exist__' @('DarkYellow')

    Enable-CommandHighlighting -CacheDurationMilliseconds 60000
    Assert-Highlight 'Test-HighlightingCommand' @("`e[31m")
    function global:Test-HighlightingCommand { throw 'Commands must not be executed' }
    Assert-Highlight 'Test-HighlightingCommand' @("`e[31m")
    # Changing location invalidates even an unexpired entry.
    Set-Location ..
    Assert-Highlight 'Test-HighlightingCommand' @()
    Set-Location $PSScriptRoot
    Remove-Item Function:/Test-HighlightingCommand

    Enable-CommandHighlighting -CacheDurationMilliseconds 60000
    Assert-Highlight 'Test-HighlightingCommand' @("`e[31m")
    function global:Test-HighlightingCommand { throw 'Commands must not be executed' }
    $originalPath = $env:PATH
    try {
        $env:PATH = $originalPath + [IO.Path]::PathSeparator + $PSScriptRoot
        Assert-Highlight 'Test-HighlightingCommand' @()
    } finally {
        $env:PATH = $originalPath
    }
    Assert-Highlight 'Test-HighlightingCommand' @()
    Remove-Item Function:/Test-HighlightingCommand
    Assert-Highlight 'Test-HighlightingCommand' @()
    $originalPathExt = $env:PATHEXT
    try {
        $env:PATHEXT = $originalPathExt + ';.HIGHLIGHTTEST'
        Assert-Highlight 'Test-HighlightingCommand' @("`e[31m")
    } finally {
        $env:PATHEXT = $originalPathExt
    }

    Enable-CommandHighlighting -CacheDurationMilliseconds 50
    Assert-Highlight 'Test-HighlightingCommand' @("`e[31m")
    function global:Test-HighlightingCommand { throw 'Commands must not be executed' }
    [Threading.Thread]::Sleep(75)
    Assert-Highlight 'Test-HighlightingCommand' @()
    Remove-Item Function:/Test-HighlightingCommand
    [Threading.Thread]::Sleep(75)
    Assert-Highlight 'Test-HighlightingCommand' @("`e[31m")

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
