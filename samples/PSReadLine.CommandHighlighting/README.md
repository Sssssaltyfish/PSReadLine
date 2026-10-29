# Command highlighting

This independent PowerShell module demonstrates the `HighlightingHandler` API. It is not
loaded by PSReadLine. Load the locally built PSReadLine in a fresh `pwsh -NoProfile -NonInteractive`
process before importing this module; an already loaded PSReadLine assembly cannot be replaced
in the same process.

```powershell
Import-Module ./bin/Debug/PSReadLine/PSReadLine.psd1
Import-Module ./samples/PSReadLine.CommandHighlighting/PSReadLine.CommandHighlighting.psd1
Enable-CommandHighlighting
```

Known commands retain their normal syntax colors. Unknown commands use the terminal palette's
red (ANSI SGR 31), so their color follows the active terminal color scheme. Each statically named command is
checked, including commands in pipelines and subexpressions. Functions, aliases, loaded
cmdlets, executables in PATH, and explicit script paths use PowerShell command discovery.
Dynamic invocations such as `& $command` retain their normal syntax colors.

```powershell
Enable-CommandHighlighting -InvalidColor '#e06c75'
Disable-CommandHighlighting
```

Results describe the current session, not what executing the line might change. For example,
`Set-Alias newCommand Get-Date; newCommand` can show `newCommand` as unknown until the alias
has actually been defined. Only already imported modules are considered: exports of modules
not yet imported may appear unknown. Highlighting does not execute expressions or import
modules to discover commands.

Each render queries the current session. Repeated command names within that render share one
lookup; results are discarded afterward. Changes to aliases, functions, files, PATH, or location
are reflected on the next render, without a time-based cache. This follows fish's approach of
checking current command availability, but runs synchronously in the user's PowerShell runspace
so its functions and aliases remain visible. Slow filesystem or network PATH entries can delay
a render. No timer, background runspace, key binding, input rewrite, or prompt hook is installed.

Enabling temporarily replaces the single highlighting callback. Disabling or removing the
module restores the previous callback if this module still owns the slot. To combine providers,
install a callback that merges their ranges instead.

## Tests

With the locally built PSReadLine imported in a fresh process, run:

```powershell
./samples/PSReadLine.CommandHighlighting/Tests.ps1
```
