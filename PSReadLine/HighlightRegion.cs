// Copyright (c) Microsoft Corporation.
// Licensed under the 2-Clause BSD License.

using System;

namespace Microsoft.PowerShell
{
    /// <summary>
    /// A color override for a half-open range of UTF-16 offsets in the input buffer.
    /// </summary>
    public sealed class HighlightRegion
    {
        public HighlightRegion(int startOffset, int endOffset, object color)
        {
            if (startOffset < 0)
            {
                throw new ArgumentOutOfRangeException(nameof(startOffset));
            }

            if (endOffset <= startOffset)
            {
                throw new ArgumentOutOfRangeException(nameof(endOffset));
            }

            StartOffset = startOffset;
            EndOffset = endOffset;
            Color = VTColorUtils.AsEscapeSequence(color);
        }

        public int StartOffset { get; }

        public int EndOffset { get; }

        public string Color { get; }
    }
}
