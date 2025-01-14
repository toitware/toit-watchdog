// Copyright (C) 2024 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

import expect show *
import watchdog show WatchdogServiceClient
import system.services show ServiceProvider ServiceHandler
import system.api.trace show TraceService

import .util

main:
  service := TraceServiceProvider
  service.install
  run-test: | client/WatchdogServiceClient ms/int system-dog/FakeSystemWatchdog |
    dog := client.create "toit.io/test/throw-close"
    dog.start --s=1
    expect-equals 0 service.traces.size
    dog.close
    expect-equals 1 service.traces.size
  service.uninstall

class TraceServiceProvider extends ServiceProvider
    implements TraceService ServiceHandler:
  traces_/List := []

  constructor:
    super "system/trace/test" --major=1 --minor=2
    provides TraceService.SELECTOR --handler=this

  handle index/int arguments/any --gid/int --client/int -> any:
    if index == TraceService.HANDLE-TRACE-INDEX:
      return handle-trace arguments
    unreachable

  traces -> List:
    result := traces_
    traces_ = []
    return result

  handle-trace message/ByteArray -> ByteArray?:
    traces_.add message
    return null
