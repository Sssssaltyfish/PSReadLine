# Custom input highlighting

`Set-PSReadLineOption -HighlightingHandler` installs an optional callback that supplies
colors for ranges of the input buffer. PSReadLine continues to parse and edit the original
input. This is a rendering extension, not command validation or input rewriting.

The callback has type `Func<Ast, HighlightRegion[]>`. It receives the syntax tree already
parsed for the current render, including incomplete input. Return `$null` or an empty array
to keep the normal syntax colors. Set the option to `$null` to remove the callback.

```powershell
Set-PSReadLineOption -HighlightingHandler {
    param($ast)
    if ($ast.Extent.Text.Length -ge 3) {
        [Microsoft.PowerShell.HighlightRegion]::new(0, 3, 'Green')
    }
}
```

Each `HighlightRegion` has an inclusive `StartOffset`, an exclusive `EndOffset`, and a
`Color`. Offsets count UTF-16 code units, just like PowerShell syntax extents. The constructor
accepts the same colors as `Set-PSReadLineOption -Colors`: console colors, RGB hex strings,
or ANSI color sequences. Start must be nonnegative and end must be greater than start.

Return regions in ascending order without overlaps. Null entries, ranges beyond the input,
and ranges starting before the end of the preceding accepted range are ignored. Gaps retain
their syntax colors. Regions can cross token and line boundaries, but do not color continuation
prompts, predictions, or status messages. Selection and search emphasis take precedence.
Screen-reader mode does not invoke the callback.

The callback runs synchronously when PSReadLine renders input, which can happen repeatedly
without a text change. Keep it fast; avoid network access, module imports, console output, or
editing the buffer. Cache expensive work in the provider when appropriate. A callback exception
falls back to syntax coloring for that render; test providers directly to diagnose errors.
Recursive rendering does not invoke the callback again.

There is one callback, like the existing history and validation handlers. A caller that needs
several highlighters can combine their results into one ordered, non-overlapping array.
