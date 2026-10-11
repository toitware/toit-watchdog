# Watchdog

A package to provide watchdog functionality for containers.

Works on ESP32 devices, the EC618, and the RP2350.

## Usage

Using the watchdog requires installing the provider and importing
the client in the applications that want to use it.

### Provider

Create a fresh provider container:

``` toit
// In watchdog-provider.toit.

import watchdog.provider

main:
  (provider.WatchdogServiceProvider).install
```

Install it with Jaguar as follows

``` bash
jag container install watchdog watchdog-provider.toit
```

### Client

Import `watchdog` and then use it as follows:

``` toit
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

  // Stop it, when not needed anymore.
  dog.stop

  // When stopped, close it.
  dog.close
```

## EC618

The default provider uses the SDK's `system.watchdog` API on EC618. Use an
SDK and firmware that include this API; the package's declared alpha.200
minimum must include it before this change can be released.

The EC618 provider accepts `--granularity-ms` from 1 through 60000 and rounds
up to whole seconds. The default 2000 ms is supported. Individual clients
can request longer timeouts; the provider checks their deadlines while
feeding the system watchdog. The SDK's watchdog task continues timing
during light sleep and runs independently of the Toit scheduler. Deep sleep
ends monitoring and waking starts a fresh boot.

Use one provider per device. Code in other containers, including test agents,
that feeds or reconfigures `system.watchdog` or `ec618.watchdog` operates on
the same watchdog and can interfere with monitoring.

See [the EC618 hardware tests](tests/ec618/README.md) for reset, cross-container,
and stop/restart qualification. Ordinary host tests use a test backend and do
not verify the native EC618 watchdog.
