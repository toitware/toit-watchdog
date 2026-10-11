# Copyright (C) 2026 Toit contributors.
# Use of this source code is governed by a Zero-Clause BSD license that can be
# found in the tests/TESTS_LICENSE file.

"""Run EC618 watchdog tests through mini-jag without interfering feed pings.

Requires pyserial, the EC618 mini-jag agent at 115200 baud, and the compiled
32-bit hardware.toit image. These tests deliberately reset the device. The
active slot must already be validated. No firmware image is changed.
"""

import argparse
from pathlib import Path
import re
import struct
import time
import zlib


class Link:
    def __init__(self, port):
        self.port = port

    def send(self, data):
        self.port.write(data)
        self.port.flush()

    def expect(self, expected, timeout=10):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            value = self.port.read(1)
            if not value or value in (b'\r', b'\n'):
                continue
            if value == b'[':
                line = bytearray(value)
                while not line.endswith(b'\n') and time.monotonic() < deadline:
                    line.extend(self.port.read(1))
                print(line.decode(errors='replace').strip(), flush=True)
                continue
            assert value == expected, (value, expected)
            return
        raise TimeoutError(f'Expected {expected!r}')

    def ping(self):
        self.send(b'P')
        self.expect(b'P')

    def install(self, image, mode):
        arg = mode.encode()
        self.send(b'A' + struct.pack('<I', len(arg)) + arg)
        self.expect(b'K')
        self.send(b'C' + struct.pack('<II', len(image), zlib.crc32(image)))
        self.expect(b'R')
        for offset in range(0, len(image), 2048):
            chunk = image[offset:offset + 2048]
            self.send(struct.pack('>I', len(chunk)) + chunk)
            self.expect(b'K')
        self.expect(b'K')

    def run(self, mode):
        self.send(b'R')
        started = time.monotonic()
        lines = []
        next_ping = started + 3
        timeout = 50 if mode == 'stopped-busy' else 13
        success = {
            'bounds': 'WATCHDOG PASS bounds/feed/stop',
            'healthy': 'WATCHDOG PASS cross-container feed/stop/restart',
            'stopped-busy': 'WATCHDOG PASS stopped during sustained CPU work',
        }
        # No commands while running: every command feeds the shared watchdog.
        # A stopped watchdog ignores feeds, so that longer phase can renew
        # the host lease without masking an unwanted hardware expiry.
        while time.monotonic() - started < timeout:
            if mode == 'stopped-busy' and time.monotonic() >= next_ping:
                self.send(b'P')
                next_ping = time.monotonic() + 3
            line = self.port.readline().decode(errors='replace').strip()
            if not line:
                continue
            print(f'{time.monotonic() - started:.3f}s {line}', flush=True)
            lines.append(line)
            joined = '\n'.join(lines)
            assert 'jag decode ' not in line, 'Test container threw'
            assert 'WATCHDOG FAILED' not in line, line
            assert 'host lease expired' not in line, line
            if '[mini-jag] run: test exited code=' in line:
                assert mode in success, 'Expected a reset'
                assert re.search(r'\[mini-jag\] run: test exited code=0$', line), joined
                assert success[mode] in joined, joined
                return
            if '[mini-jag] ec618 ready ' in line:
                if mode in ('idle', 'busy'):
                    assert f'WATCHDOG ARMED {mode}' in joined, joined
                    assert 'FATAL: watchdog timeout (2000 ms without feed)' in joined, joined
                elif mode == 'abandoned':
                    assert 'WATCHDOG ABANDONED CLIENT EXITED' in joined, joined
                    assert 'WATCHDOG BACKEND REBOOT' in joined, joined
                    assert 'FATAL: watchdog timeout (1000 ms without feed)' in joined, joined
                elif mode == 'reboot':
                    assert 'WATCHDOG REBOOT REQUESTED' in joined, joined
                    assert 'WATCHDOG BACKEND REBOOT' in joined, joined
                    assert 'FATAL: watchdog timeout (1000 ms without feed)' in joined, joined
                else:
                    raise AssertionError('Unexpected reboot: ' + joined)
                return
        raise TimeoutError(f'{mode}: no conclusive verdict before host lease expiry')


def main():
    import serial

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', required=True)
    parser.add_argument('--image', required=True, type=Path)
    parser.add_argument('--mode', choices=['bounds', 'healthy', 'abandoned', 'idle', 'busy', 'reboot', 'stopped-busy'])
    args = parser.parse_args()
    image = args.image.read_bytes()
    port = serial.Serial(port=None, baudrate=115200, timeout=.1, write_timeout=5)
    port.dtr = False
    port.rts = False
    port.port = args.port
    port.open()
    try:
        link = Link(port)
        link.ping()
        link.send(b'T')
        link.expect(b'n')  # Do not deliberately reset an unvalidated trial.
        for mode in ([args.mode] if args.mode else ['bounds', 'healthy', 'abandoned', 'idle', 'busy', 'reboot', 'stopped-busy']):
            print(f'BEGIN {mode}', flush=True)
            link.install(image, mode)
            link.run(mode)
            link.ping()
            print(f'PASS {mode}', flush=True)
    finally:
        port.close()


if __name__ == '__main__':
    main()
