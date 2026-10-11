// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can be
// found in the tests/TESTS_LICENSE file.

import crypto.crc
import io

MODES ::= ["bounds", "healthy", "abandoned", "idle", "busy", "reboot", "stopped-busy"]
SUCCESS ::= {
  "bounds": "WATCHDOG PASS bounds/feed/stop",
  "healthy": "WATCHDOG PASS cross-container feed/stop/restart",
  "stopped-busy": "WATCHDOG PASS stopped during sustained CPU work",
}

// The transport provides send, read-byte, read-line, now-ms and log. Host
// tests use deterministic traces and a virtual clock without serial hardware.
class Link:
  transport_/any
  constructor .transport_:

  expect expected/int -> none:
    deadline := transport_.now-ms + 10_000
    status-line := false
    while transport_.now-ms < deadline:
      value := transport_.read-byte
      if value == null: continue
      if status-line:
        if value == '\n': status-line = false
        continue
      if value == '\r' or value == '\n': continue
      if value == '[':
        status-line = true
        continue
      if value != expected: throw "Unexpected acknowledgement: $value, expected $expected"
      return
    throw "TIMEOUT"

  ping:
    transport_.send #[ 'P' ]
    expect 'P'

  require-validated-slot:
    transport_.send #[ 'T' ]
    expect 'n'

  install image/ByteArray mode/string:
    if not MODES.contains mode or image.is-empty: throw "INVALID_ARGUMENT"
    argument := mode.to-byte-array
    header := ByteArray 4
    io.LITTLE-ENDIAN.put-uint32 header 0 argument.size
    transport_.send (#[ 'A' ] + header + argument)
    expect 'K'
    checksum := crc.Crc32
    checksum.add image
    io.LITTLE-ENDIAN.put-uint32 header 0 image.size
    transport_.send (#[ 'C' ] + header + checksum.get)
    expect 'R'
    offset := 0
    while offset < image.size:
      end := min image.size (offset + 2048)
      io.BIG-ENDIAN.put-uint32 header 0 (end - offset)
      transport_.send (header + image[offset..end])
      expect 'K'
      offset = end
    expect 'K'

  run mode/string:
    if not MODES.contains mode: throw "INVALID_ARGUMENT"
    transport_.send #[ 'R' ]
    started := transport_.now-ms
    next-ping := started + 3000
    timeout := mode == "stopped-busy" ? 50_000 : 13_000
    lines := []
    while transport_.now-ms - started < timeout:
      // Every command feeds the watchdog. Only the stopped phase may renew
      // the host lease; armed phases must reach their verdict without pings.
      if mode == "stopped-busy" and transport_.now-ms >= next-ping:
        transport_.send #[ 'P' ]
        next-ping = transport_.now-ms + 3000
      line := transport_.read-line
      if not line: continue
      transport_.log "$(transport_.now-ms - started)ms $line"
      lines.add line
      joined := lines.join "\n"
      if line.contains "jag decode " or line.contains "WATCHDOG FAILED" or line.contains "host lease expired":
        throw "Failed phase: $line"
      if line.contains "[mini-jag] run: test exited code=":
        marker := SUCCESS.get mode
        if not marker or not line.ends-with "[mini-jag] run: test exited code=0" or not joined.contains marker:
          throw "Inconclusive exit: $joined"
        return
      if line.contains "[mini-jag] ec618 ready ":
        if mode == "idle" or mode == "busy":
          require-marker_ joined "WATCHDOG ARMED $mode"
          require-marker_ joined "FATAL: watchdog timeout (2000 ms without feed)"
        else if mode == "abandoned" or mode == "reboot":
          require-marker_ joined (mode == "abandoned" ? "WATCHDOG ABANDONED CLIENT EXITED" : "WATCHDOG REBOOT REQUESTED")
          require-marker_ joined "WATCHDOG BACKEND REBOOT"
          require-marker_ joined "FATAL: watchdog timeout (1000 ms without feed)"
        else:
          throw "Unexpected reboot: $joined"
        return
    throw "TIMEOUT"

  require-marker_ text/string marker/string:
    if not text.contains marker: throw "Missing $marker in $text"
