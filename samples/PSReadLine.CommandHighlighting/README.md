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

`-InvalidColor` accepts an ANSI color sequence, a console color name (such as
`DarkYellow`), or an RGB hex color. The default is ANSI SGR 31. To share PSReadLine's
configured error color, use `Enable-CommandHighlighting -InvalidColor (Get-PSReadLineOption).ErrorColor`.
Put the desired invocation in your profile after importing the module; enabling again
applies the new settings and clears the lookup cache. Known commands are never recolored.

Results describe the current session, not what executing the line might change. For example,
`Set-Alias newCommand Get-Date; newCommand` can show `newCommand` as unknown until the alias
has actually been defined. Only already imported modules are considered: exports of modules
not yet imported may appear unknown. Highlighting does not execute expressions or import
modules to discover commands.

Command lookups run synchronously in the user's PowerShell runspace. Results are cached for
1,000 milliseconds by default, with at most 256 entries. Repeated command names within a render
also share one lookup. PATH, PATHEXT, or location changes clear the cache immediately.

Use `-CacheDurationMilliseconds` to configure the lifetime (0 through 60,000). A value of 0
disables cross-render caching. Expiration is measured from lookup completion; cache hits do
not extend it. Function, alias, or file changes can remain cached until the first render after
expiration. There is no timer that forces a redraw while idle. Enabling again clears the cache.

```powershell
Enable-CommandHighlighting -InvalidColor "`e[31m" -CacheDurationMilliseconds 1000
```

Caching reduces repeated synchronous discovery while editing arguments, correcting input,
or moving the cursor. New command names and expired entries still require a lookup; slow
filesystem or network PATH entries can delay those renders. No background runspace, key binding,
input rewrite, or prompt hook is installed.

Enabling temporarily replaces the single highlighting callback. Disabling or removing the
module restores the previous callback if this module still owns the slot. To combine providers,
install a callback that merges their ranges instead.

## Tests

With the locally built PSReadLine imported in a fresh process, run:

```powershell
./samples/PSReadLine.CommandHighlighting/Tests.ps1
```
