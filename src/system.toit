// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

import system.watchdog

import .provider show SystemWatchdog

/** Implements the system watchdog using the SDK's portable watchdog API. */
class SystemWatchdogEmbedded implements SystemWatchdog:
  start --ms/int:
    watchdog.start --timeout=(Duration --ms=ms)

  feed -> none:
    watchdog.feed

  stop -> none:
    watchdog.stop

  reboot -> none:
    // Use a fresh short deadline so the reset does not depend on how much of
    // the provider's normal feeding interval remains.
    watchdog.start --timeout=(Duration --s=1)
    sleep (Duration --s=10)
