# Reverse-engineering and technical notes

## Scope

These notes document observations from one Lenovo IdeaPad Pro 5 16AHP9, DMI
model `LENOVO 83D5`. They are not Lenovo specifications and must not be
generalized to other products without independent testing.

No proprietary Lenovo binaries, disassembly, or decompiled code are included.
This document records only independently described behavior and the resulting
Linux userspace implementation.

AI assistance was used substantially to analyze observations, generate and
eliminate hypotheses, debug experiments, implement the controller, review its
failure handling, and write this documentation. The user performed the actual
experiments and verified the behavior on physical hardware.

## System under test

- Lenovo IdeaPad Pro 5 16AHP9 (`LENOVO 83D5`)
- AMD Ryzen 7 8845HS
- NVIDIA GeForce RTX 4050 Laptop GPU, 6 GB
- Dual-fan cooling system
- CachyOS Linux with Linux 7.2.x
- Lenovo `VPC2004` ACPI interface exposed through `ideapad_laptop`

## Control path

The runtime path is:

```text
lenovo-max-fan userspace process
  -> Linux sysfs fan_mode attribute
  -> ideapad_laptop / Lenovo VPC2004 interface
  -> embedded controller and platform firmware
  -> two physical fans
```

On the tested system, the relevant sysfs node is:

```text
/sys/devices/pci0000:00/0000:00:14.3/PNP0C09:00/VPC2004:00/fan_mode
```

The VPC behavior observed during investigation corresponds to command `0x22`
for setting fan mode and `0x2B` for reading it. The released controller does not
issue those commands directly; it uses the Linux kernel's existing sysfs
attribute.

## Request values and readback states

The request value and the subsequent readback are not numerically identical:

| Requested write | Observed readback | Observed meaning |
| --- | ---: | --- |
| `0` | `133` | NORMAL, firmware-controlled fan behavior |
| `1` | `3` | FAST/cleaning high-speed cycle |

The controller therefore verifies state transitions by readback. It records the
NORMAL readback at startup, requires NORMAL to return to that value, and accepts
FAST only after the readback differs from NORMAL. The confirmed values on the
test machine were NORMAL=`133` and FAST=`3`.

These are firmware state encodings, not RPM or PWM percentages.

## Fan behavior and timing

The two fans reached approximately 6,800–7,100 RPM in FAST mode. FAST is a
firmware-managed cleaning cycle rather than a persistent manual-speed setting:
after roughly ten seconds near maximum, the firmware naturally begins to ramp
the fans down and later back up.

Experiments found:

- repeatedly writing `1` did not restart the active FAST cycle;
- an immediate unconfirmed `0` → `1` transition sometimes failed to latch and
  allowed a deep RPM trough;
- waiting for confirmed NORMAL, then confirmed FAST, made retriggering reliable;
- a monotonic 8.5-second interval kept both fans near 6,800–7,100 RPM most of
  the time, with brief transition dips commonly around 5,900–6,300 RPM.

The 8.5-second value is empirical and specific to the tested firmware. It is
not a safe compatibility default for an untested model.

During investigation, embedded-controller telemetry at offsets `0x06` and
`0xFE` tracked fan 1 and fan 2 as RPM divided by 100 on this machine. Those
offsets are not accessed by the released controller and must not be assumed to
have the same meaning elsewhere.

## Alternatives investigated

Normal Linux platform profiles changed the thermal/performance policy but did
not expose the observed maximum fan behavior. No supported generic hwmon/PWM
manual fan interface was available on the tested system.

An apparent Lenovo `WMB5` manual-RPM path reported success during experiments,
but the firmware ignored or replaced the requested RPM. A separate Lenovo DYTC
cooling-boost function was rejected by this firmware. Neither became part of
the solution.

The practical result is therefore policy in userspace: retrigger the firmware's
existing FAST/cleaning state through the already exposed VPC sysfs interface.
It does not set a target RPM.

## Controller sequence

1. Confirm that the exact `fan_mode` path exists.
2. Confirm that external AC power is online.
3. Request NORMAL (`0`), wait 200 ms, and record the NORMAL readback.
4. Confirm NORMAL, then request and confirm FAST (`1`).
5. Wait 8.5 seconds using a monotonic clock while checking AC power.
6. Confirm NORMAL and immediately confirm FAST again.
7. Repeat until stopped or until a safety check fails.
8. In a `finally` block, request NORMAL (`0`).

The loop checks AC power at least every 50 ms while waiting and during state
confirmation. Transition confirmation times out after one second.

## Failure handling

The process handles `SIGINT`, `SIGTERM`, and `SIGHUP`, and its `finally` block
attempts `fan_mode=0` after normal exit, handled signals, AC removal, missing
confirmation, and other controller-level failures.

Because a process cannot clean up after `SIGKILL`, the systemd service also runs:

```text
ExecStopPost=/usr/local/sbin/lenovo-max-fan --reset
```

This independent reset was experimentally verified after forcibly killing the
main process: systemd invoked the reset helper and the interface returned to
NORMAL readback `133`.

No software cleanup can be guaranteed after sudden power loss, a kernel crash,
or loss of the firmware/sysfs interface. The service is therefore installed as
disabled and should be started manually.

## Compatibility boundary

Only `LENOVO 83D5` has been tested. Another model may use a different path,
state encoding, timing, fan topology, or entirely different semantics for the
same-looking interface. A marketing-family name such as “IdeaPad” is not enough
evidence of compatibility. Treat every other system as unsupported and
experimental until its behavior and cleanup path have been independently
verified.
