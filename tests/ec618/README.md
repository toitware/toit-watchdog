# EC618 watchdog hardware tests

Use an EC618 SDK and matching firmware with `system.watchdog`, and the resident
mini-jag hardware-test agent. These tests intentionally reset the board, so the
active firmware slot must already be validated. The runner checks that before
starting.

Compile `hardware.toit` from this directory with the matching SDK:

```sh
toit compile -O2 -s -o hardware.snapshot hardware.toit
toit tool snapshot-to-image --format=binary -m32 -o hardware.image hardware.snapshot
python3 run-hardware.py --port /dev/serial/by-id/VERIFIED_DEVICE --image hardware.image
```

Use the actual persistent serial path identifying the EC618; a by-path link
may be needed for adapters without unique serial numbers. The agent must be
listening at 115200 baud. The Python runner requires `pyserial`.

The phases cover timeout boundaries, feeding and stopping, clients in separate
containers, stop/restart, an armed client's exit, idle and CPU-busy expiry,
reboot from a stopped watchdog, and 40 seconds of CPU work after stopping,
beyond both native watchdog windows.
Select one phase with `--mode`.

The ordinary mini-jag runner sends keep-alive pings that also feed the system
watchdog. This runner suppresses them during armed-watchdog tests. Each such
phase is bounded below the agent's 15-second host lease; the longer stopped
phase renews the lease while the application watchdog is disabled.

A reset alone is not a pass. Native expiry requires the 2000 ms watchdog
fatal message, followed by a new agent-ready banner. Abandoned-client expiry
requires proof that the client exited and that the provider called the real
shared reboot method, followed by the 1000 ms watchdog fatal message.
The direct reboot phase also requires that one-second fatal message after
requesting a reset with the watchdog previously stopped. Non-reset tests
require both their phase-specific success marker and a zero container exit
status. Every phase ends with an agent ping.

This directory is deliberately outside the package's host CTest glob because
these tests need EC618 support and hardware. The host tests use a test backend;
they do not exercise these native reset paths. A successful compile also does
not qualify hardware behavior.

These tests deliberately replace the agent's application-watchdog settings.
Only the runner should own the serial port, and no other watchdog provider
should run during the test. Acquire the test rig's normal exclusive lock if
it is shared with other runners.

Run `python3 test-runner.py` without hardware to check that incomplete or
contradictory serial traces cannot produce a successful verdict. These checks
use only the Python standard library.
