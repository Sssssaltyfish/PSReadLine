// Copyright (c) Microsoft Corporation.
// Licensed under the 2-Clause BSD License.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;

namespace Microsoft.PowerShell
{
    // Recognize paste boundaries before the platform map interprets control keys.
    internal sealed class BracketedPasteCharMap : ICharMap
    {
        private const string Start = "\x1b[200~";
        private const string End = "\x1b[201~";
        private readonly ConsoleKeyInfo[] _prefix = new ConsoleKeyInfo[Start.Length];
        private readonly Queue<ConsoleKeyInfo> _keys = new Queue<ConsoleKeyInfo>();
        private readonly Stopwatch _timer = new Stopwatch();
        private int _prefixLength;
        private int _endLength;
        private StringBuilder _paste;
        private string _completedPaste;
        private readonly ICharMap _transport;
        private readonly ICharMap _keyMap;

        internal BracketedPasteCharMap(ICharMap inner, long escapeTimeout, bool win32Input = false)
        {
            Inner = inner;
            EscapeTimeout = escapeTimeout;
            _transport = win32Input ? inner : null;
            _keyMap = win32Input ? new DotNetCharMap() : inner;
        }

        internal ICharMap Inner { get; }
        public long EscapeTimeout { get; set; }
        public bool InEscapeSequence => _prefixLength > 0 || _keyMap.InEscapeSequence ||
            (_transport?.InEscapeSequence ?? false);

        public bool KeyAvailable
        {
            get
            {
                PumpTransport();
                if (_prefixLength > 0 && _timer.ElapsedMilliseconds >= EscapeTimeout)
                {
                    FlushPrefix();
                    ExpireInnerEscape();
                }

                return HasInput;
            }
        }

        private bool HasInput => _keys.Count > 0 || _keyMap.KeyAvailable || _completedPaste != null;

        public ConsoleKeyInfo ReadKey() => _keys.Count > 0 ? _keys.Dequeue() : _keyMap.ReadKey();

        internal string ReadPaste()
        {
            // A preceding ordinary key must be delivered before the paste.
            if (_keys.Count > 0 || _keyMap.KeyAvailable)
            {
                return null;
            }

            string text = _completedPaste;
            _completedPaste = null;
            return text;
        }

        public void ProcessKey(ConsoleKeyInfo key)
        {
            if (_transport == null)
            {
                ProcessDecodedKey(key);
            }
            else
            {
                _transport.ProcessKey(key);
                PumpTransport();
            }
        }

        private void PumpTransport()
        {
            if (_transport != null)
            {
                while (!HasInput && _transport.KeyAvailable)
                {
                    ProcessDecodedKey(_transport.ReadKey());
                }
            }
        }

        private void ProcessDecodedKey(ConsoleKeyInfo key)
        {
            if (_paste != null)
            {
                char c = key.KeyChar;
                if (c == End[_endLength])
                {
                    if (++_endLength == End.Length)
                    {
                        _completedPaste = _paste.ToString();
                        _paste = null;
                        _endLength = 0;
                    }
                }
                else
                {
                    _paste.Append(End, 0, _endLength);
                    _endLength = 0;
                    if (c == End[0])
                    {
                        _endLength = 1;
                    }
                    else
                    {
                        _paste.Append(c);
                    }
                }

                return;
            }

            if (key.KeyChar == Start[_prefixLength])
            {
                if (_prefixLength == 0)
                {
                    DrainInner();
                    _timer.Restart();
                }

                _prefix[_prefixLength++] = key;
                if (_prefixLength == Start.Length)
                {
                    // A key preceding the paste must not be overtaken by it.
                    ExpireInnerEscape();
                    _prefixLength = 0;
                    _paste = new StringBuilder();
                }
            }
            else
            {
                FlushPrefix();
                if (key.KeyChar == Start[0])
                {
                    ProcessDecodedKey(key);
                    return;
                }
                _keyMap.ProcessKey(key);
                DrainInner();
            }
        }

        private void FlushPrefix()
        {
            for (int i = 0; i < _prefixLength; i++)
            {
                _keyMap.ProcessKey(_prefix[i]);
                DrainInner();
            }

            _prefixLength = 0;
        }

        private void DrainInner()
        {
            while (_keyMap.KeyAvailable)
            {
                _keys.Enqueue(_keyMap.ReadKey());
            }
        }

        private void ExpireInnerEscape()
        {
            long timeout = _keyMap.EscapeTimeout;
            _keyMap.EscapeTimeout = 0;
            DrainInner();
            _keyMap.EscapeTimeout = timeout;
        }
    }
}
