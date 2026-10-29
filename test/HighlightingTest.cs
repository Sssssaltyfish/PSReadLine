// Copyright (c) Microsoft Corporation.
// Licensed under the 2-Clause BSD License.

using System;
using Microsoft.PowerShell;
using Xunit;

namespace Test
{
    public partial class ReadLine
    {
        [SkippableFact]
        public void HighlightingOverridesSyntaxColors()
        {
            Skip.If(ScreenReaderModeEnabled);
            TestSetup(KeyMode.Cmd);
            string input = null;
            PSConsoleReadLine.SetOptions(new SetPSReadLineOption
            {
                HighlightingHandler = ast =>
                {
                    input = ast.Extent.Text;
                    return new[] { new HighlightRegion(0, 3, MakeCombinedColor(ConsoleColor.Green, _console.BackgroundColor)) };
                }
            });

            Test("abc 123", Keys("abc 123", CheckThat(() =>
            {
                Assert.Equal("abc 123", input);
                AssertScreenIs(1,
                    Tuple.Create(ConsoleColor.Green, _console.BackgroundColor), "abc",
                    TokenClassification.None, " ",
                    TokenClassification.Number, "123");
            })));
        }

        [SkippableFact]
        public void HighlightingIgnoresInvalidRegions()
        {
            Skip.If(ScreenReaderModeEnabled);
            TestSetup(KeyMode.Cmd);
            PSConsoleReadLine.SetOptions(new SetPSReadLineOption
            {
                HighlightingHandler = ast => new[]
                {
                    null,
                    new HighlightRegion(0, int.MaxValue, ConsoleColor.Red),
                    new HighlightRegion(1, 2, MakeCombinedColor(ConsoleColor.Green, _console.BackgroundColor)),
                    new HighlightRegion(0, 3, ConsoleColor.Red), // Unordered and overlapping.
                    new HighlightRegion(2, 3, MakeCombinedColor(ConsoleColor.Blue, _console.BackgroundColor)),
                }
            });

            Test("abc", Keys("abc", CheckThat(() => AssertScreenIs(1,
                TokenClassification.Command, "a",
                Tuple.Create(ConsoleColor.Green, _console.BackgroundColor), "b",
                Tuple.Create(ConsoleColor.Blue, _console.BackgroundColor), "c"))));
        }

        [SkippableFact]
        public void HighlightingFailureFallsBackToSyntaxColors()
        {
            Skip.If(ScreenReaderModeEnabled);
            TestSetup(KeyMode.Cmd);
            PSConsoleReadLine.SetOptions(new SetPSReadLineOption
            {
                HighlightingHandler = ast => throw new InvalidOperationException("Broken highlighter")
            });
            Test("abc", Keys("abc", CheckThat(() => AssertScreenIs(1, TokenClassification.Command, "abc"))));

            PSConsoleReadLine.SetOptions(new SetPSReadLineOption { HighlightingHandler = ast => null });
            Test("abc", Keys("abc", CheckThat(() => AssertScreenIs(1, TokenClassification.Command, "abc"))));

            PSConsoleReadLine.SetOptions(new SetPSReadLineOption { HighlightingHandler = null });
            Assert.Null(PSConsoleReadLine.GetOptions().HighlightingHandler);
        }

        [SkippableFact]
        public void HighlightingPreservesSelectionAndSearchEmphasis()
        {
            Skip.If(ScreenReaderModeEnabled);
            TestSetup(KeyMode.Cmd,
                new KeyHandler("UpArrow", PSConsoleReadLine.HistorySearchBackward));
            var green = Tuple.Create(ConsoleColor.Green, _console.BackgroundColor);
            PSConsoleReadLine.SetOptions(new SetPSReadLineOption
            {
                HighlightingHandler = ast => ast.Extent.Text.Length == 0 ? null : new[]
                {
                    new HighlightRegion(0, ast.Extent.Text.Length,
                        MakeCombinedColor(ConsoleColor.Green, _console.BackgroundColor))
                }
            });
            Test("abc", Keys("abc", _.Shift_Home,
                CheckThat(() => AssertScreenIs(1, Selected("abc"))), _.End,
                CheckThat(() => AssertScreenIs(1, green, "abc"))));

            SetHistory("abc");
            Test("abc", Keys("a", _.UpArrow, CheckThat(() => AssertScreenIs(1,
                Tuple.Create(PSConsoleReadLineOptions.DefaultEmphasisColor, _console.BackgroundColor), "a",
                green, "bc"))));
        }

        [SkippableFact]
        public void HighlightingIsNotInvokedForScreenReaders()
        {
            Skip.IfNot(ScreenReaderModeEnabled);
            TestSetup(KeyMode.Cmd);
            bool called = false;
            PSConsoleReadLine.SetOptions(new SetPSReadLineOption
            {
                HighlightingHandler = ast => { called = true; return null; }
            });
            Test("abc", Keys("abc"));
            Assert.False(called);
        }

        [SkippableFact]
        public void HighlightingSpansLinesAndRestoresSyntaxColor()
        {
            Skip.If(ScreenReaderModeEnabled);
            TestSetup(KeyMode.Cmd);
            PSConsoleReadLine.SetOptions(new SetPSReadLineOption
            {
                HighlightingHandler = ast => new[]
                {
                    new HighlightRegion(1, 6, MakeCombinedColor(ConsoleColor.Green, _console.BackgroundColor))
                }
            });
            Test("abc\ndef", Keys("abc", _.Shift_Enter, "def", CheckThat(() => AssertScreenIs(2,
                TokenClassification.Command, "a",
                Tuple.Create(ConsoleColor.Green, _console.BackgroundColor), "bc", NextLine,
                Tuple.Create(_console.ForegroundColor, _console.BackgroundColor), PSConsoleReadLineOptions.DefaultContinuationPrompt,
                Tuple.Create(ConsoleColor.Green, _console.BackgroundColor), "de",
                TokenClassification.Command, "f"))));
        }
    }

    public class HighlightRegionTests
    {
        [Fact]
        public void ValidateOffsets()
        {
            Assert.Throws<ArgumentOutOfRangeException>(() => new HighlightRegion(-1, 1, ConsoleColor.Red));
            Assert.Throws<ArgumentOutOfRangeException>(() => new HighlightRegion(1, 1, ConsoleColor.Red));
            Assert.Throws<ArgumentOutOfRangeException>(() => new HighlightRegion(2, 1, ConsoleColor.Red));
        }
    }
}
