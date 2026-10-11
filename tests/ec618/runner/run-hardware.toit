// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can be
// found in the tests/TESTS_LICENSE file.

import host.file
import uart
import .link

main args:
  options := {:}
  if args.size % 2 != 0: throw "Expected --port PATH --image PATH [--mode MODE]"
  for index := 0; index < args.size; index += 2:
    key := args[index]
    if not ["--port", "--image", "--mode"].contains key or options.contains key:
      throw "Invalid or duplicate option: $key"
    options[key] = args[index + 1]
  if not options.contains "--port" or not options.contains "--image":
    throw "Expected --port PATH --image PATH [--mode MODE]"
  mode := options.get "--mode"
  if mode and not MODES.contains mode: throw "Unknown mode: $mode"
  image := file.read-contents options["--image"]
  transport := SerialTransport options["--port"]
  try:
    link := Link transport
    link.ping
    link.require-validated-slot
    (mode ? [mode] : MODES).do: |phase/string|
      print "BEGIN $phase"
      link.install image phase
      link.run phase
      link.ping
      print "PASS $phase"
  finally:
    transport.close

class SerialTransport:
  port_/uart.HostPort
  pending_/ByteArray := #[]

  constructor path/string:
    port_ = uart.HostPort path --baud-rate=115200
    initialized := false
    try:
      port_.set-control-flag uart.HostPort.CONTROL-FLAG-DTR false
      port_.set-control-flag uart.HostPort.CONTROL-FLAG-RTS false
      initialized = true
    finally:
      if not initialized: port_.close

  now-ms -> int: return Time.monotonic-us / 1000
  log message/string: print message
  close: port_.close

  send bytes/ByteArray:
    with-timeout --ms=5000:
      port_.out.write bytes
      port_.out.flush

  read-byte -> int?:
    result/int? := null
    catch --unwind=(: it != DEADLINE-EXCEEDED-ERROR):
      result = with-timeout --ms=100: port_.in.read-byte
      if result == null: throw "Serial port closed"
    return result

  read-line -> string?:
    deadline := now-ms + 100
    while now-ms < deadline:
      byte := read-byte
      if byte == null: return null
      if byte == '\n':
        result := pending_.to-string.trim
        pending_ = #[]
        return result
      pending_ += #[byte]
    return null
