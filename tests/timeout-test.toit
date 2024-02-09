// Copyright (C) 2024 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

import expect show *
import watchdog show WatchdogServiceClient

import .util

main:
  run-test: |client ms hw-dog| test-timeout client ms hw-dog

test-timeout client/WatchdogServiceClient ms/int hw-dog/FakeHardwareWatchdog:
  dog := client.create "toit.io/test/timeout"
  dog.start --s=1
  hw-dog.signal.wait: hw-dog.failed
  hw-dog.signal.wait: hw-dog.reboot-initiated
  dog.stop
  dog.close
