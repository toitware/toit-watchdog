// Copyright (C) 2024 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

import expect show *
import watchdog show WatchdogServiceClient

import .util

main:
  run-test: |client ms system-dog| test-timeout client ms system-dog

test-timeout client/WatchdogServiceClient ms/int system-dog/FakeSystemWatchdog:
  dog := client.create "toit.io/test/timeout"
  dog.start --s=1
  system-dog.signal.wait: system-dog.failed
  system-dog.signal.wait: system-dog.reboot-initiated
  dog.stop
  dog.close
