// Copyright (C) 2024 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

import esp32

import .provider show HardwareWatchdog

class HardwareWatchdogEsp32 implements HardwareWatchdog:
  start --ms/int:
    esp32.watchdog-init --ms=ms

  feed -> none:
    esp32.watchdog-reset

  stop -> none:
    esp32.watchdog-deinit

  reboot -> none:
    esp32.deep-sleep Duration.ZERO
