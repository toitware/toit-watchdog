// Copyright (C) 2024 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

import expect show *
import watchdog show WatchdogServiceClient

import .util

main:
  run-test: |client ms hw-dog| test-many client ms hw-dog

test-many client/WatchdogServiceClient ms/int hw-dog/FakeHardwareWatchdog:
  dogs := List 20: client.create "toit.io/test/many/$it"
  dogs.do: it.start --s=1
  4.repeat:
    dogs.do: it.feed
    sleep --ms=500
  dogs.do: it.stop
  dogs.do: it.close

  expect-not hw-dog.failed
  expect-not hw-dog.reboot-initiated
