// Copyright (C) 2024 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

import expect show *
import watchdog show WatchdogServiceClient

import .util

main:
  run-test: |client ms system-dog| test-many-one-timeout client ms system-dog

test-many-one-timeout client/WatchdogServiceClient ms/int system-dog/FakeSystemWatchdog:
  dogs := List 20: client.create "toit.io/test/many-one-timeout/$it"
  failing-dog := client.create "toit.io/test/many-one-timeout/failing"
  dogs.do: it.start --s=1
  failing-dog.start --s=1
  4.repeat:
    dogs.do: it.feed
    sleep --ms=500
  dogs.do: it.stop
  dogs.do: it.close
  failing-dog.stop
  failing-dog.close

  expect system-dog.failed
  expect system-dog.reboot-initiated

