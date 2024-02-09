// Copyright (C) 2024 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

import monitor
import watchdog.provider
import watchdog show WatchdogServiceClient

class FakeHardwareWatchdog implements provider.HardwareWatchdog:
  // For simplicity we use the signal for internal and external
  // notifications.
  signal/monitor.Signal := monitor.Signal
  task_/Task? := null
  feed-count_/int := 0
  failed/bool := false
  reboot-initiated/bool := false

  start --ms/int:
    task_ = task::
      e := catch:
        while true:
          old-feed-count := feed-count_
          with-timeout --ms=ms:
            signal.wait: old-feed-count != feed-count_
      // Timeout.
      failed = true
      signal.raise

  feed -> none:
    feed-count_++
    signal.raise

  stop -> none:
    task_.cancel

  reboot -> none:
    failed = true
    reboot-initiated = true
    stop
    signal.raise

run-test [block]:
  granularity-ms := 500
  fake-hardware-dog := FakeHardwareWatchdog
  service-provider := provider.WatchdogServiceProvider
      --granularity-ms=granularity-ms
      --hardware-watchdog=fake-hardware-dog
  service-provider.install
  client := (WatchdogServiceClient).open
  try:
    with-timeout --ms=5_000:
      block.call client granularity-ms fake-hardware-dog
  finally:
    client.close
    service-provider.uninstall

