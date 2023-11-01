# Watchdog

A package to provide watchdog functionality for containers.

Only works on an actual ESP.

## Usage

Using the watchdog requires to install the provider and then to
import the client in the applications that want to use it.

### Provider

Either install the `src/provider.toit` as container directly (mainly
useful with Artemis), or create a fresh provider container:

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

  // Stop it, if not necessary:
  dog.stop

  // When stopped, close it.
  dog.close
```
