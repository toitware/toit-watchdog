// Copyright (C) 2024 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

import expect show *
import watchdog show WatchdogServiceClient

import .util

main:
  run-test: |client ms system-dog| test-recover client ms system-dog

// If a watchdog gets lost/closed, another watchdog with the same name can take over.
test-recover client/WatchdogServiceClient ms/int system-dog/FakeSystemWatchdog:
  dog := client.create "toit.io/test/recover"
  dog.start --s=1
  // Simulate a crash/loss and just create a new dog with the same new name.
  dog2 := client.create "toit.io/test/recover"

  4.repeat:
    dog2.feed
    sleep --ms=500

  dog2.stop
  dog2.close
  dog.stop
  dog.close

  expect-not system-dog.failed
  expect-not system-dog.reboot-initiated
