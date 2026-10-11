# Copyright (C) 2026 Toit contributors.
# Use of this source code is governed by a Zero-Clause BSD license that can be
# found in the tests/TESTS_LICENSE file.

"""Exercise verdicts and keep-alive behavior with synthetic serial traces."""

from collections import deque
from contextlib import redirect_stdout
import importlib.util
import io
from pathlib import Path
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    'hardware_runner', Path(__file__).with_name('run-hardware.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

READY = '[mini-jag] ec618 ready test-firmware'
EXIT = '[mini-jag] run: test exited code=0'
FATAL_1S = '[toit] FATAL: watchdog timeout (1000 ms without feed) — resetting'
FATAL_2S = '[toit] FATAL: watchdog timeout (2000 ms without feed) — resetting'


class SerialTrace:
    def __init__(self, lines):
        self.lines = deque((line + '\n').encode() for line in lines)
        self.writes = []
        self.now = 0

    def readline(self):
        self.now += .25
        return self.lines.popleft() if self.lines else b''

    def write(self, data):
        self.writes.append(data)

    def flush(self):
        pass


class VerdictTests(unittest.TestCase):
    def run_trace(self, mode, lines, error=None):
        trace = SerialTrace(lines)
        with patch.object(runner.time, 'monotonic', lambda: trace.now):
            with redirect_stdout(io.StringIO()):
                if error:
                    with self.assertRaises(error):
                        runner.Link(trace).run(mode)
                else:
                    runner.Link(trace).run(mode)
        if mode != 'stopped-busy':
            self.assertEqual(trace.writes, [b'R'], 'Armed tests must not send feed pings')
        return trace

    def test_native_expiry_requires_armed_marker_fatal_and_ready(self):
        for mode in ('idle', 'busy'):
            lines = [f'WATCHDOG ARMED {mode}', FATAL_2S, READY]
            with self.subTest(mode=mode):
                self.run_trace(mode, lines)
            for missing in range(len(lines)):
                with self.subTest(mode=mode, missing=missing):
                    self.run_trace(mode, lines[:missing] + lines[missing + 1:],
                                   TimeoutError if missing == 2 else AssertionError)

    def test_provider_reboot_requires_one_second_deadline(self):
        for mode, marker in (
                ('abandoned', 'WATCHDOG ABANDONED CLIENT EXITED'),
                ('reboot', 'WATCHDOG REBOOT REQUESTED')):
            lines = [marker, 'WATCHDOG BACKEND REBOOT', FATAL_1S, READY]
            with self.subTest(mode=mode):
                self.run_trace(mode, lines)
                self.run_trace(mode, [marker, 'WATCHDOG BACKEND REBOOT', FATAL_2S, READY],
                               AssertionError)
            for missing in range(len(lines)):
                with self.subTest(mode=mode, missing=missing):
                    self.run_trace(mode, lines[:missing] + lines[missing + 1:],
                                   TimeoutError if missing == 3 else AssertionError)

    def test_non_reset_phases_require_own_marker_and_zero_exit(self):
        for mode, marker in (
                ('bounds', 'WATCHDOG PASS bounds/feed/stop'),
                ('healthy', 'WATCHDOG PASS cross-container feed/stop/restart'),
                ('stopped-busy', 'WATCHDOG PASS stopped during sustained CPU work')):
            with self.subTest(mode=mode):
                self.run_trace(mode, [marker, EXIT])
                self.run_trace(mode, [marker], TimeoutError)
                self.run_trace(mode, [EXIT], AssertionError)
                self.run_trace(mode, ['WATCHDOG PASS unrelated phase', EXIT], AssertionError)
                self.run_trace(mode, [marker, EXIT[:-1] + '1'], AssertionError)
                self.run_trace(mode, [marker, EXIT + '1'], AssertionError)
                self.run_trace(mode, [marker, READY], AssertionError)

    def test_normal_exit_is_not_an_expiry(self):
        self.run_trace('idle', ['WATCHDOG ARMED idle', EXIT], AssertionError)

    def test_errors_cannot_be_hidden_by_later_success(self):
        for error in ('jag decode exception', 'WATCHDOG FAILED TO RESET',
                      'host lease expired'):
            with self.subTest(error=error):
                self.run_trace('idle', ['WATCHDOG ARMED idle', error, FATAL_2S, READY],
                               AssertionError)

    def test_stopped_phase_renews_host_lease(self):
        trace = self.run_trace('stopped-busy', [''] * 160 + [
            'WATCHDOG PASS stopped during sustained CPU work', EXIT])
        self.assertEqual(trace.writes[0], b'R')
        self.assertGreaterEqual(trace.writes.count(b'P'), 12)


if __name__ == '__main__':
    unittest.main()
