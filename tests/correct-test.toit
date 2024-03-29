// Copyright (C) 2024 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

import expect show *
import watchdog show WatchdogServiceClient

import .util

main:
  run-test: |client ms system-dog| test-correct-feeding client ms system-dog

test-correct-feeding client/WatchdogServiceClient ms/int system-dog/FakeSystemWatchdog:
  dog := client.create "toit.io/test/correct"
  dog.start --s=1
  4.repeat:
    dog.feed
    sleep --ms=500
  dog.stop
  dog.close

  expect-not system-dog.failed
  expect-not system-dog.reboot-initiated
