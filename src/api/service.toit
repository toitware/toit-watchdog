// Copyright (C) 2023 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

import system.services show ServiceSelector

interface WatchdogService:
  static SELECTOR ::= ServiceSelector
      --uuid="d11a26d3-9552-46f0-8d52-3cb925f1b04c"
      --major=1
      --minor=0

  create id/string -> int
  static CREATE-INDEX ::= 0

  start handle/int max-ms/int -> none
  static START-INDEX ::= 1

  feed handle/int -> none
  static FEED-INDEX ::= 2

  stop handle/int -> none
  static STOP-INDEX ::= 3
