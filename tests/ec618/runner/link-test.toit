// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can be
// found in the tests/TESTS_LICENSE file.

import expect show *
import io
import .link

READY ::= "[mini-jag] ec618 ready test-firmware"
EXIT ::= "[mini-jag] run: test exited code=0"
FATAL-1S ::= "[toit] FATAL: watchdog timeout (1000 ms without feed) — resetting"
FATAL-2S ::= "[toit] FATAL: watchdog timeout (2000 ms without feed) — resetting"

class Trace:
  lines/List
  writes := []
  now-ms/int := 0
  acknowledgements/ByteArray := #[]
  line-index_/int := 0
  ack-index_/int := 0
  constructor .lines:
  send bytes/ByteArray: writes.add bytes.copy
  log message/string: null
  read-line -> string?:
    now-ms += 250
    if line-index_ >= lines.size: return null
    return lines[line-index_++]
  read-byte -> int?:
    now-ms += 1
    if ack-index_ >= acknowledgements.size: return null
    return acknowledgements[ack-index_++]

run-trace mode/string lines/List --fails/bool=false --timeout/bool=false -> Trace:
  trace := Trace lines
  error := catch: (Link trace).run mode
  if timeout:
    expect-equals "TIMEOUT" error
  else if fails:
    expect error != null
  else:
    expect-equals null error
  if mode != "stopped-busy": expect-equals [#[ 'R' ]] trace.writes
  return trace

main:
  ["idle", "busy"].do: |mode/string|
    lines := ["WATCHDOG ARMED $mode", FATAL-2S, READY]
    run-trace mode lines
    lines.size.repeat: |missing/int|
      run-trace mode (lines[..missing] + lines[missing + 1..])
          --fails
          --timeout=(missing == 2)
  [["abandoned", "WATCHDOG ABANDONED CLIENT EXITED"],
    ["reboot", "WATCHDOG REBOOT REQUESTED"]].do: |phase/List|
    mode/string := phase[0]
    lines := [phase[1], "WATCHDOG BACKEND REBOOT", FATAL-1S, READY]
    run-trace mode lines
    run-trace mode [phase[1], "WATCHDOG BACKEND REBOOT", FATAL-2S, READY] --fails
    lines.size.repeat: |missing/int|
      run-trace mode (lines[..missing] + lines[missing + 1..])
          --fails
          --timeout=(missing == 3)
  SUCCESS.do: |mode/string marker/string|
    run-trace mode [marker, EXIT]
    run-trace mode [marker] --timeout
    run-trace mode [EXIT] --fails
    run-trace mode ["WATCHDOG PASS unrelated phase", EXIT] --fails
    run-trace mode [marker, "[mini-jag] run: test exited code=1"] --fails
    run-trace mode [marker, "$EXIT" + "1"] --fails
    run-trace mode [marker, READY] --fails
  run-trace "idle" ["WATCHDOG ARMED idle", EXIT] --fails
  ["jag decode exception", "WATCHDOG FAILED TO RESET", "host lease expired"].do:
    run-trace "idle" ["WATCHDOG ARMED idle", it, FATAL-2S, READY] --fails
  trace := run-trace "stopped-busy" ((List 160: "") + [SUCCESS["stopped-busy"], EXIT])
  expect-equals #[ 'R' ] trace.writes[0]
  expect trace.writes.size >= 13
  trace.writes[1..].do: expect-equals #[ 'P' ] it

  // Independent protocol examples check endianness, CRC and acknowledgements.
  transport := Trace []
  transport.acknowledgements = #[ 'K', 'R', 'K', 'K' ]
  (Link transport).install "123456789".to-byte-array "bounds"
  expect-equals (#[ 'A', 6, 0, 0, 0 ] + "bounds".to-byte-array) transport.writes[0]
  expect-equals #[ 'C', 9, 0, 0, 0, 0x26, 0x39, 0xf4, 0xcb ] transport.writes[1]
  expect-equals (#[0, 0, 0, 9] + "123456789".to-byte-array) transport.writes[2]
  transport = Trace []
  transport.acknowledgements = #[ 'K', 'R', 'K', 'K', 'K', 'K' ]
  image := ByteArray 4097: it & 255
  (Link transport).install image "idle"
  expect-equals 5 transport.writes.size
  expect-equals 2048 (io.BIG-ENDIAN.uint32 transport.writes[2] 0)
  expect-equals 2048 (io.BIG-ENDIAN.uint32 transport.writes[3] 0)
  expect-equals 1 (io.BIG-ENDIAN.uint32 transport.writes[4] 0)
  expect-equals image (transport.writes[2][4..] + transport.writes[3][4..] + transport.writes[4][4..])
  transport = Trace []
  transport.acknowledgements = "\r\n[mini-jag] status\nP".to-byte-array
  (Link transport).ping
  transport = Trace []
  transport.acknowledgements = #[ 't' ]
  expect (catch: (Link transport).require-validated-slot) != null
  transport = Trace []
  expect-equals "TIMEOUT" (catch: (Link transport).ping)
  print "PASS: seven phase verdicts, missing/contradictory evidence, feed suppression, lease renewal and install protocol"
