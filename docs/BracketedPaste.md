# Bracketed paste

Enable terminal-originated paste as a single edit with:

```powershell
Set-PSReadLineOption -EnableBracketedPaste $true
```

The option defaults to `$false`. It takes effect the next time PSReadLine reads
input. The terminal must support bracketed paste (for example, Windows Terminal).
Its existing paste shortcuts and context-menu action can remain unchanged.
Pasted newlines are inserted into the edit buffer; press Enter to accept the
input. A paste replaces the selection, if any, and can be undone as one edit.
As with the `Paste` function, tabs are expanded to four spaces. CRLF, LF, and CR
line endings are normalized to LF.

On Windows, this requires a console supporting both bracketed paste and
`win32-input-mode`, such as a current Windows Terminal/ConPTY installation.
PSReadLine enables VT input and requests Win32 key records so that keys such as
Ctrl+Backspace, Shift+Enter, and Ctrl+[ retain their modifiers and virtual key
codes. The existing Windows ANSI translator decodes these records before paste
boundaries are recognized. Console characters are read in batches to avoid a
native console call for every character of an encoded key record. Setting the
option to `$false` restores the input
behavior selected by the host and `PSREADLINE_VTINPUT` on the next prompt.

On Unix, boundary recognition depends on the terminal and .NET's `Console.ReadKey`
preserving the bracketed-paste markers. Windows Terminal/ConPTY is the validated
configuration for this implementation; Unix hosts have not been validated.

PSReadLine enables the protocol while editing and disables it when it returns
input or invokes a potentially external application. The parser keeps paste
contents out of key bindings and waits for the complete end marker, including
when a paste spans multiple reads. The protocol does not escape its own end
marker: an embedded `ESC[201~` ends a paste. Terminals are responsible for
sanitizing clipboard control characters; this feature is not a security boundary.

Design discussions: [PSReadLine #1471](https://github.com/PowerShell/PSReadLine/issues/1471),
[PSReadLine #579](https://github.com/PowerShell/PSReadLine/issues/579), and
[dotnet/runtime #73257](https://github.com/dotnet/runtime/pull/73257).
