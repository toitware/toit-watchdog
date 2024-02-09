// Copyright (C) 2023 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

import log
import monitor
import system.services show ServiceProvider ServiceResource ServiceHandler
import .api.service
import .esp32 show SystemWatchdogEsp32

interface SystemWatchdog:
  /**
  Starts the hardware watchdog timer.

  The watchdog will reset the system if it isn't fed within $ms milliseconds.
  The hardware watchdog may have a coarser granularity than the given $ms.
  */
  start --ms/int

  /**
  Feeds the hardware watchdog.

  # Aliases
  - `kick`
  - `reset`
  */
  feed -> none

  /**
  Stops the hardware watchdog.
  */
  stop -> none

  /**
  Reboots the system.

  This is called if a watchdog isn't fed in time, but the system
    watchdog still has time left.
  */
  reboot -> none

class WatchdogServiceProvider extends ServiceProvider
  implements ServiceHandler:

  static GRANULARITY-MS ::= 2_000

  dogs_/Map ::= {:}  // From string to Watchdog.
  system-watchdog_/SystemWatchdog
  system-watchdog-task_/Task? := null
  logger_/log.Logger
  mutex_/monitor.Mutex ::= monitor.Mutex
  granularity-ms_/int

  constructor
      --logger/log.Logger=((log.default.with-name "watchdog").with-level log.ERROR-LEVEL)
      --system-watchdog/SystemWatchdog = SystemWatchdogEsp32
      --granularity-ms/int = GRANULARITY-MS:
    logger_ = logger
    system-watchdog_ = system-watchdog
    granularity-ms_ = granularity-ms
    super "watchdog" --major=1 --minor=0
    provides WatchdogService.SELECTOR --handler=this

  handle index/int arguments/any --gid/int --client/int -> any:
    if index == WatchdogService.CREATE-INDEX:
      id := arguments[0] as string
      dog/Watchdog := ?
      if dogs_.contains id:
        // There exists already a watchdog with this id.
        // Remove it and replace it with a fresh one.
        // However, the new watchdog will be in the same state as the old one.
        old-dog := dogs_[id]
        dogs_.remove id
        dog = Watchdog.clone this client old-dog
      else:
        dog = Watchdog this client id
      dogs_[id] = dog
      logger_.info "created watchdog" --tags={ "id": id }
      return dog

    if index == WatchdogService.START-INDEX:
      dog := (this.resource client arguments[0]) as Watchdog
      dog.start (arguments[1] as int)
      start-system-watchdog-if-necessary_
      logger_.info "started watchdog" --tags={ "id": dog.id }
      return null

    if index == WatchdogService.FEED-INDEX:
      dog := (this.resource client arguments[0]) as Watchdog
      dog.feed
      logger_.info "fed watchdog" --tags={ "id": dog.id }
      return null

    if index == WatchdogService.STOP-INDEX:
      dog := (this.resource client arguments[0]) as Watchdog
      dog.stop
      stop-system-watchdog-if-possible_
      logger_.info "stopped watchdog" --tags={ "id": dog.id }
      return null

    unreachable

  start-system-watchdog-if-necessary_:
    if system-watchdog-task_: return

    mutex_.do:
      logger_.debug "starting hardware watchdog"
      system-watchdog_.start --ms=granularity-ms_
      system-watchdog-task_ = task::
        try:
          while true:
            too-late := false
            dogs_.do --values: | dog/Watchdog |
              if dog.is-too-late:
                logger_.error "watchdog too late" --tags={ "id": dog.id }
                too-late = true

            if too-late:
              // Feed the hardware watchdog one last time then request to reboot.
              // This allows the system to clean up before rebooting.
              mutex_.do: system-watchdog_.feed
              system-watchdog_.reboot
            else:
              // Feed the hardware watchdog.
              logger_.debug "feeding hardware watchdog"
              mutex_.do: system-watchdog_.feed
              sleep --ms=(granularity-ms_ / 2)
        finally:
          system-watchdog-task_ = null

  stop-system-watchdog-if-possible_:
    if not system-watchdog-task_: return

    needs-watching := dogs_.any: | _ dog/Watchdog | not dog.is-stopped
    if needs-watching: return

    // Shutdown the hardware watchdog.
    mutex_.do:
      logger_.info "stopping hardware watchdog"
      system-watchdog_.stop

      system-watchdog-task_.cancel

  remove-dog_ dog/Watchdog:
    logger_.info "removing watchdog" --tags={ "id": dog.id }
    dogs_.remove dog.id

class Watchdog extends ServiceResource:
  /** The watchdog is started. */
  static STATE-STARTED ::= 0
  /** The watchdog is stopped. */
  static STATE-STOPPED ::= 1
  /**
  The watchdog wasn't fed in time.

  Feeding or stopping at this point is too late.
  */
  static STATE-TOO-LATE ::= 2

  provider/WatchdogServiceProvider
  id/string

  state/int := STATE-STOPPED
  last-feeding-us/int := -1
  max-sleep-us/int := -1

  constructor .provider client/int .id:
    super provider client

  constructor.clone .provider client/int other/Watchdog:
    id = other.id
    state = other.state
    last-feeding-us = other.last-feeding-us
    max-sleep-us = other.max-sleep-us

    super provider client

  start s/int:
    if is-too-late: return
    if state != STATE-STARTED:
      state = STATE-STARTED
      // Only feed if the watchdog wasn't started yet.
      last-feeding-us = Time.monotonic-us
    max-sleep-us = s * Duration.MICROSECONDS-PER-SECOND

  feed -> none:
    if state != STATE-STARTED: return
    now-us := Time.monotonic-us
    if now-us - last-feeding-us > max-sleep-us:
      state = STATE-TOO-LATE
      return
    last-feeding-us = Time.monotonic-us

  stop -> none:
    if not is-too-late:
      state = STATE-STOPPED

  is-too-late -> bool:
    return state == STATE-TOO-LATE or
      (state == STATE-STARTED and Time.monotonic-us - last-feeding-us > max-sleep-us)

  is-stopped -> bool:
    return state == STATE-STOPPED

  on-closed -> none:
    // This would normally lead to a memory leak: we are not removing
    // the dog even though it is closed. However, the whole point of
    // the watchdog is to reset the system if the application hangs
    // or crashes. Not closing the watchdog correctly is a sign of a
    // crash. We need to reboot.
    if state == STATE-STOPPED and not is-too-late:
      provider.remove-dog_ this

main:
  provider := WatchdogServiceProvider
  provider.install
