# lenovo-max-fan

A small Linux userspace controller that keeps Lenovo's VPC FAST/cleaning fan
mode active by safely retriggering it through the kernel's `fan_mode` sysfs
interface.

> [!CAUTION]
> **This software has been tested on exactly one machine: DMI model `LENOVO
> 83D5`.** It is experimental on every other model. Lenovo firmware interfaces
> are undocumented and model-specific; sysfs paths, write values, readback
> states, timings, and physical behavior may differ. Do not assume that another
> Lenovo laptop is compatible merely because it exposes a file named
> `fan_mode`. Review the code and technical notes before running it.

This is not a generic fan-curve or RPM controller. On the tested machine,
`fan_mode=1` starts the firmware's built-in FAST/cleaning cycle. The controller
briefly returns to NORMAL and re-enters FAST every 8.5 seconds so the firmware
does not reach the low-speed part of that cycle.

## Tested hardware

The tested configuration was:

- Lenovo IdeaPad Pro 5 16AHP9
- DMI model `LENOVO 83D5`
- AMD Ryzen 7 8845HS
- NVIDIA GeForce RTX 4050 Laptop GPU, 6 GB
- Dual-fan cooling system
- CachyOS Linux
- Linux 7.2.x
- Lenovo `VPC2004` interface exposed by the Linux `ideapad_laptop` driver

## Observed behavior on `LENOVO 83D5`

- NORMAL is requested by writing `0`; the firmware reads back `133`.
- FAST is requested by writing `1`; the firmware reads back `3`.
- FAST produced approximately 6,800–7,100 RPM across the two fans.
- A NORMAL → FAST retrigger every 8.5 seconds kept the fans near that range,
  with brief dips during transitions.
- Rewriting FAST alone did not restart the firmware cycle.

These numbers are observations, not a specification. See
[the technical notes](docs/technical-notes.md) for the evidence and limitations.

## Safety design

The controller:

- starts only while external AC power is present and keeps checking for it;
- confirms firmware readback after NORMAL and FAST requests;
- writes `fan_mode=0` on normal exit, handled signals, and controller errors;
- has an independent systemd `ExecStopPost` reset, including when the main
  process is killed;
- uses only the kernel-exposed VPC sysfs interface at runtime—no direct EC
  writes, `acpi_call`, proprietary binaries, or reverse-engineering tools; and
- is installed but neither enabled nor started automatically.

The cleanup cannot run after power loss, a kernel crash, or failure of the
firmware/sysfs interface. The laptop's own thermal protections remain essential.
Maximum fan operation is loud and may increase fan wear.

## Requirements

- Linux with Lenovo VPC fan mode exposed at the exact path used in
  [`lenovo-max-fan`](lenovo-max-fan)
- Python 3
- systemd
- root privileges to write the sysfs fan interface
- external AC power

## Install

First inspect `lenovo-max-fan`, `lenovo-max-fan.service`, and `install.sh`.
Then run:

```sh
sudo ./install.sh
```

The installer copies the controller to `/usr/local/sbin/lenovo-max-fan`, copies
the unit to `/etc/systemd/system/lenovo-max-fan.service`, and reloads systemd.
It deliberately does not enable or start the service.

## Use

Start sustained FAST mode manually:

```sh
sudo systemctl start lenovo-max-fan.service
```

Check status and recent messages:

```sh
systemctl status lenovo-max-fan.service
journalctl -u lenovo-max-fan.service -n 30 --no-pager
```

Stop and restore normal firmware control:

```sh
sudo systemctl stop lenovo-max-fan.service
```

Do not enable the service at boot until you have independently established
that your exact hardware and firmware behave safely.

## AI assistance and human verification

AI assistance was used substantially during reverse engineering, hypothesis
generation, debugging, implementation, safety review, and documentation. The
result should not be treated as authoritative vendor documentation.

The reported behavior and safety paths were experimentally verified by the user
on real `LENOVO 83D5` hardware, including readback states, fan-speed behavior,
the 8.5-second retrigger, normal shutdown cleanup, and systemd cleanup after the
main process was forcibly killed. No claim is made for other machines.

## Contributing

Reports from other systems are welcome, but please remove serial numbers,
usernames, home-directory paths, and other personal identifiers. Include the
exact DMI model, laptop marketing name, kernel version, VPC interface path,
observed request/readback states, timing, AC-power behavior, and how normal fan
control was restored. Never upload proprietary Lenovo binaries or decompiled
vendor code.

## License

Copyright (C) 2026 lenovo-max-fan contributors.

This project is licensed under the GNU General Public License v3.0 only
(`GPL-3.0-only`). See [LICENSE](LICENSE).
