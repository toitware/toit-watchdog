// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import watchdog show WatchdogServiceClient

main:
  client := WatchdogServiceClient
  // Connect to the provider that has been started earlier.
  client.open
  dog := client.create "my-dog"

  // Require a feeding every 3 seconds.
  dog.start --s=3

  3.repeat:
    print "Feeding"
    dog.feed
    sleep --ms=500

  // Not feeding, so going to die.
  print "Not feeding anymore"
