// Copyright (c) Microsoft Corporation.
// Licensed under the 2-Clause BSD License.

using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.PowerShell;
using Xunit;

namespace Test
{
    public class BracketedPasteCharMapTest
    {
        private static void Feed(ICharMap map, string text)
        {
            foreach (char c in text)
            {
                map.ProcessKey(new ConsoleKeyInfo(c, 0, false, false, false));
            }
        }

        [Theory]
        [InlineData("")]
        [InlineData("one\r\ntwo\n")]
        [InlineData("\t\x03\x7f\x1b[A\x1b[201x\x1b\x1b[200~")]
        [InlineData("中文😀")]
        public void PasteIsLiteralAndWaitsForEnd(string text)
        {
            var map = new BracketedPasteCharMap(new WindowsAnsiCharMap(), 10000);
            Feed(map, "\x1b[200~" + text);
            Assert.False(map.KeyAvailable);
            Feed(map, "\x1b[201~");
            Assert.True(map.KeyAvailable);
            Assert.Equal(text, map.ReadPaste());
            Assert.False(map.KeyAvailable);
        }

        [Fact]
        public void LargePasteAndAdjacentInput()
        {
            var map = new BracketedPasteCharMap(new DotNetCharMap(), 10000);
            string text = new string('x', 100000);
            Feed(map, "a");
            Assert.Null(map.ReadPaste());
            Assert.Equal('a', map.ReadKey().KeyChar);
            for (int i = 0; i < 2; i++)
            {
                Feed(map, "\x1b[200~" + text + "\x1b[201~");
                Assert.Equal(text, map.ReadPaste());
            }
            Feed(map, "b");
            Assert.Equal('b', map.ReadKey().KeyChar);
        }

        [Fact]
        public void EscapeImmediatelyBeforePasteKeepsItsOrder()
        {
            var map = new BracketedPasteCharMap(new WindowsAnsiCharMap(10000), 10000);
            Feed(map, "\x1b\x1b[200~text\x1b[201~");
            Assert.Null(map.ReadPaste());
            Assert.Equal(ConsoleKey.Escape, map.ReadKey().Key);
            Assert.Equal("text", map.ReadPaste());
            Assert.False(map.KeyAvailable);
        }

        [Theory]
        [InlineData("\x1b[8;14;127;1;8;1_", ConsoleKey.Backspace, '\x7f', ConsoleModifiers.Control)]
        [InlineData("\x1b[13;28;13;1;16;1_", ConsoleKey.Enter, '\r', ConsoleModifiers.Shift)]
        [InlineData("\x1b[219;26;27;1;8;1_", ConsoleKey.Oem4, '\x1b', ConsoleModifiers.Control)]
        [InlineData("\x1b[37;75;0;1;264;1_", ConsoleKey.LeftArrow, '\0', ConsoleModifiers.Control)]
        [InlineData("\x1b[39;77;0;1;258;1_", ConsoleKey.RightArrow, '\0', ConsoleModifiers.Alt)]
        [InlineData("\x1b[18;56;233;0;0;1_", (ConsoleKey)18, 'é', (ConsoleModifiers)0)]
        public void Win32KeysPreserveModifiers(string input, ConsoleKey key, char character, ConsoleModifiers modifiers)
        {
            var map = new WindowsAnsiCharMap(10000) { Win32InputMode = true };
            Feed(map, input);
            Assert.True(map.KeyAvailable);
            var actual = map.ReadKey();
            Assert.Equal(key, actual.Key);
            Assert.Equal(character, actual.KeyChar);
            Assert.Equal(modifiers, actual.Modifiers);
            Assert.False(map.KeyAvailable);
        }

        [Fact]
        public void Win32KeyUpModifiersAndRepeatCount()
        {
            var map = new WindowsAnsiCharMap(10000) { Win32InputMode = true };
            Feed(map, "\x1b[16;42;0;1;16;1_");
            Assert.False(map.KeyAvailable);
            Feed(map, "\x1b[65;30;97;0;0;1_");
            Assert.False(map.KeyAvailable);
            Feed(map, "\x1b[65;30;97;1;0;3_");
            for (int i = 0; i < 3; i++)
            {
                Assert.True(map.KeyAvailable);
                Assert.Equal('a', map.ReadKey().KeyChar);
            }
            Assert.False(map.KeyAvailable);
        }

        [Fact]
        public void Win32EncodedPasteRetainsLiteralCharacters()
        {
            var transport = new WindowsAnsiCharMap(10000) { Win32InputMode = true };
            var map = new BracketedPasteCharMap(transport, 10000, win32Input: true);
            string text = "中文😀\r\n\t\x03\x1b[A";
            foreach (char c in "\x1b[200~" + text + "\x1b[201~")
            {
                Feed(map, $"\x1b[0;0;{(int)c};1;0;1_");
            }
            Assert.Equal(text, map.ReadPaste());
            Assert.False(map.KeyAvailable);
        }

        [Fact]
        public void LargeWin32PasteAndFollowingKey()
        {
            var transport = new WindowsAnsiCharMap(10000) { Win32InputMode = true };
            var map = new BracketedPasteCharMap(transport, 10000, win32Input: true);
            string text = new string('x', 100000);
            foreach (char c in "\x1b[200~" + text)
            {
                Feed(map, $"\x1b[0;0;{(int)c};1;0;1_");
                Assert.False(map.KeyAvailable);
            }
            foreach (char c in "\x1b[201~")
            {
                Feed(map, $"\x1b[0;0;{(int)c};1;0;1_");
            }
            Assert.Equal(text, map.ReadPaste());
            Feed(map, "\x1b[13;28;13;1;0;1_");
            Assert.Equal(ConsoleKey.Enter, map.ReadKey().Key);
            Assert.False(map.KeyAvailable);
        }

        [Theory]
        [InlineData("\x1b[97;79;49;1;2;1_")]
        [InlineData("\x1b[35;79;0;1;2;1_")]
        public void Win32AltNumpadWaitsForComposedCharacter(string input)
        {
            var map = new WindowsAnsiCharMap(10000) { Win32InputMode = true };
            Feed(map, input);
            Assert.False(map.KeyAvailable);
            Feed(map, "\x1b[18;56;233;0;0;1_");
            Assert.Equal('é', map.ReadKey().KeyChar);
            Assert.False(map.KeyAvailable);
        }

        [Theory]
        [InlineData("\x1b[A", ConsoleKey.UpArrow, false)]
        [InlineData("\x1b[1;5D", ConsoleKey.LeftArrow, true)]
        [InlineData("\x03", ConsoleKey.C, true)]
        public void OrdinaryKeysUsePlatformMap(string input, ConsoleKey key, bool control)
        {
            var map = new BracketedPasteCharMap(new WindowsAnsiCharMap(10000), 10000);
            Feed(map, input);
            Assert.True(map.KeyAvailable);
            Assert.Null(map.ReadPaste());
            var actual = map.ReadKey();
            Assert.Equal(key, actual.Key);
            Assert.Equal(control, (actual.Modifiers & ConsoleModifiers.Control) != 0);
            Assert.False(map.KeyAvailable);
        }

        [Fact]
        public void IncompleteStartExpiresButPasteDoesNot()
        {
            var map = new BracketedPasteCharMap(new WindowsAnsiCharMap(10000), 10000);
            Feed(map, "\x1b[");
            map.EscapeTimeout = 0;
            Assert.True(map.KeyAvailable);
            var altBracket = map.ReadKey();
            Assert.Equal('[', altBracket.KeyChar);
            Assert.Equal(ConsoleModifiers.Alt, altBracket.Modifiers);
            Assert.False(map.KeyAvailable);

            map.EscapeTimeout = 10000;
            Feed(map, "\x1b[200~one\n");
            map.EscapeTimeout = 0;
            Assert.False(map.KeyAvailable);
            Assert.False(map.InEscapeSequence);
            Feed(map, "two\x1b[201~");
            Assert.Equal("one\ntwo", map.ReadPaste());
        }
    }

    public partial class ReadLine
    {
        private object[] TerminalPasteKeys(params object[] input)
        {
            var keys = Keys(input);
            if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) return keys;
            var result = new List<object>();
            foreach (var item in keys)
            {
                if (item is ConsoleKeyInfo key)
                {
                    int state = ((key.Modifiers & ConsoleModifiers.Shift) != 0 ? 16 : 0) |
                        ((key.Modifiers & ConsoleModifiers.Control) != 0 ? 8 : 0) |
                        ((key.Modifiers & ConsoleModifiers.Alt) != 0 ? 2 : 0);
                    foreach (var c in StringToCKI($"\x1b[{(int)key.Key};0;{(int)key.KeyChar};1;{state};1_"))
                        result.Add(c);
                }
                else result.Add(item);
            }
            return result.ToArray();
        }

        [SkippableFact]
        public void BracketedPasteMultilineUndo()
        {
            TestSetup(KeyMode.Cmd);
            PSConsoleReadLine.SetOptions(new SetPSReadLineOption { EnableBracketedPaste = true, AnsiEscapeTimeout = 10000 });
            Test("prefix", TerminalPasteKeys("prefix",
                StringToCKI("\x1b[200~one\r\ntwo\rthree\n\x1b[201~"),
                CheckThat(() => {
                    PSConsoleReadLine.GetBufferState(out string line, out int cursor);
                    Assert.Equal("prefixone\ntwo\nthree\n", line);
                    Assert.Equal(line.Length, cursor);
                }),
                _.Ctrl_z));
        }

        [SkippableFact]
        public void BracketedPasteReplacesSelection()
        {
            TestSetup(KeyMode.Cmd);
            PSConsoleReadLine.SetOptions(new SetPSReadLineOption { EnableBracketedPaste = true, AnsiEscapeTimeout = 10000 });
            Test("old", TerminalPasteKeys("old", _.Ctrl_a,
                StringToCKI("\x1b[200~new\nline\x1b[201~"),
                CheckThat(() => {
                    PSConsoleReadLine.GetBufferState(out string line, out int cursor);
                    Assert.Equal("new\nline", line);
                }),
                _.Ctrl_z));
        }

        [SkippableFact]
        public void BracketedPasteReplacesCompletionSelection()
        {
            Skip.If(ScreenReaderModeEnabled, "Menu completions are not supported in screen reader mode.");
            TestSetup(KeyMode.Cmd, new KeyHandler("Ctrl+Spacebar", PSConsoleReadLine.MenuComplete));
            PSConsoleReadLine.SetOptions(new SetPSReadLineOption { EnableBracketedPaste = true, AnsiEscapeTimeout = 10000 });
            Test("Get-Many42", TerminalPasteKeys("Get-Many", _.Ctrl_Spacebar,
                StringToCKI("\x1b[200~42\x1b[201~")));
        }
    }
}
