// Copyright (C) 2023 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

/**
A watchdog library.

Using the watchdog requires to install the provider and then to
  import the client in the applications that want to use it.

# Provider

Create a fresh provider container:

```
// In watchdog-provider.toit.

import watchdog.provider

main:
  (provider.WatchdogServiceProvider).install
```

Install it with Jaguar as follows

``` bash
jag container install watchdog watchdog-provider.toit
```

# Client

Import `watchdog` and then use it as follows:

```
import watchdog show WatchdogServiceClient

main:
  client := WatchdogServiceClient
  // Connect to the provider that has been started earlier.
  client.open
  dog := client.create "my-dog"

  // Require a feeding every 60 seconds.
  dog.start --s=60

  // Feed it:
  dog.feed

  // Stop it, if not necessary:
  dog.stop

  // When stopped, close it.
  dog.close
```
*/

import system.services show ServiceClient ServiceResourceProxy

import .api.service

class WatchdogServiceClient extends ServiceClient:
  static SELECTOR ::= WatchdogService.SELECTOR

  constructor selector=SELECTOR:
    assert: selector.matches SELECTOR
    super selector

  /**
  Creates a new watchdog with the given $id.

  The $id is used for debugging purposes, and to recover a watchdog
    if an application crashed but was restarted in time: if there
    exists already an old watchdog with the same ID, then the old
    one is removed and the returned watchdog replaces it. If the
    old watchdog was running, the new watchdog is also running.

  This watchdog must be started with $Watchdog.start, and must then be
    fed ($Watchdog.feed) at least once every `s` seconds (given to
    $Watchdog.start).

  If the watchdog is not fed in time, the system will be rebooted.

  The watchdog can be stopped with $Watchdog.stop, and can be started again
    with $Watchdog.start.
  */
  create id/string -> Watchdog:
    handle := invoke_ WatchdogService.CREATE-INDEX [id]
    proxy := Watchdog.private_ this handle
    return proxy

  start_ handle/int max-s/int:
    invoke_ WatchdogService.START-INDEX [handle, max-s]

  feed_ handle/int:
    invoke_ WatchdogService.FEED-INDEX [handle]

  stop_ handle/int:
    invoke_ WatchdogService.STOP-INDEX [handle]

/**
A watchdog.

Requires to be fed ($feed) in time to ensure that the system doesn't reboot.
*/
class Watchdog extends ServiceResourceProxy:

  constructor.private_ client/ServiceClient handle/int:
    super client handle

  /**
  Starts the watchdog.

  The watchdog must be fed ($feed) at least once every $s seconds.
  Note that exiting the application without stopping the watchdog will
    eventually lead to a reboot.

  If the watchdog was already started it will receive the new
    configuration, but it will not be fed.

  The granularity of the system may be higher than the given $s. It
    might take a few seconds before a missing feed is detected and/or
    reacted upon.
  */
  start --s/int -> none:
    client := (client_ as WatchdogServiceClient)
    client.start_ handle_ s

  /**
  Feeds the watchdog.

  Does nothing if the watchdog is not started.
  */
  feed -> none:
    client := (client_ as WatchdogServiceClient)
    client.feed_ handle_

  /**
  Stops the watchdog.

  Does nothing if the watchdog is not started.
  */
  stop -> none:
    client := (client_ as WatchdogServiceClient)
    client.stop_ handle_
