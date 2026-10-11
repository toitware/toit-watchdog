// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can be
// found in the tests/TESTS_LICENSE file.

import expect show *
import system.watchdog
import system.containers
import watchdog show WatchdogServiceClient
import watchdog.system show SystemWatchdogEmbedded
import watchdog.provider show WatchdogServiceProvider

// Run only with a host runner that stops sending mini-jag keep-alive pings.
// Reset phases are shorter than mini-jag's 15-second host lease. Only the
// stopped-busy phase permits keep-alives. Restore the agent's 60-second
// watchdog on normal exit; after a reset the agent restores it.
main args:
  if args is Map:
    client-test args["mode"]
    return
  mode := args[0]
  backend := ReportingWatchdog
  try:
    if mode == "stopped-busy":
      backend.start --ms=1001
      backend.stop
      print "WATCHDOG STOPPED BUSY"
      deadline := Time.monotonic-us + 40_000_000
      while Time.monotonic-us < deadline: null
      print "WATCHDOG PASS stopped during sustained CPU work"
    else if mode == "idle" or mode == "busy":
      backend.start --ms=1001
      print "WATCHDOG ARMED $mode"
      if mode == "idle":
        sleep --ms=8000
      else:
        deadline := Time.monotonic-us + 8_000_000
        while Time.monotonic-us < deadline: null
      throw "WATCHDOG FAILED TO RESET"
    else if mode == "reboot":
      // Reboot must arm a fresh short deadline even after the watchdog stops.
      backend.start --ms=60_000
      backend.feed
      backend.stop
      print "WATCHDOG REBOOT REQUESTED"
      backend.reboot
      throw "WATCHDOG FAILED TO REBOOT"
    else if mode == "bounds":
      [-1, 0, 60_001, 0x7fff_ffff].do: |ms/int|
        expect-equals "INVALID_ARGUMENT" (catch: backend.start --ms=ms)
      [1, 999, 1000, 1001, 60_000].do: |ms/int|
        backend.start --ms=ms
        backend.feed
        backend.stop
      backend.start --ms=1001
      12.repeat:
        sleep --ms=250
        backend.feed
      backend.stop
      sleep --ms=3000
      print "WATCHDOG PASS bounds/feed/stop"
    else if mode == "healthy" or mode == "abandoned":
      provider := WatchdogServiceProvider --system-watchdog=backend
      provider.install
      try:
        child := containers.start containers.current {"mode": mode}
        expect-equals 0 child.wait
        if mode == "healthy":
          sleep --ms=3000
          print "WATCHDOG PASS cross-container feed/stop/restart"
        else:
          print "WATCHDOG ABANDONED CLIENT EXITED"
          sleep --ms=8000
          throw "WATCHDOG FAILED TO REBOOT AFTER CLIENT EXIT"
      finally:
        provider.uninstall
    else:
      throw "INVALID_ARGUMENT"
  finally:
    watchdog.start --timeout=(Duration --s=60)

class ReportingWatchdog extends SystemWatchdogEmbedded:
  reboot -> none:
    print "WATCHDOG BACKEND REBOOT"
    super

client-test mode/string:
  client := WatchdogServiceClient
  client.open
  dog := client.create "ec618-hardware"
  dog.start --s=1
  if mode == "abandoned":
    // Leave an armed resource behind when this container exits.
    print "WATCHDOG CLIENT LEAVING ARMED DOG"
    return
  2.repeat:
    4.repeat:
      sleep --ms=250
      dog.feed
    dog.stop
    if it == 0: dog.start --s=1
  dog.close
  client.close
