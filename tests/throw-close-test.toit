// Copyright (C) 2024 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

import expect show *
import watchdog show WatchdogServiceClient

import .util

main:
  run-test: | client/WatchdogServiceClient ms/int system-dog/FakeSystemWatchdog |
    dog := client.create "toit.io/test/throw-close"
    dog.start --s=1
    expect-throw "WATCHDOG_NOT_STOPPED":
      dog.close
