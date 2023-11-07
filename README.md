# Watchdog

A package to provide watchdog functionality for containers.

Only works on ESP32 devices, including variants such as the ESP32-S3.

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
