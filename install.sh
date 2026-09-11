#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu

if [ "$(id -u)" -ne 0 ]; then
    printf '%s\n' 'error: install.sh must be run as root' >&2
    exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

install -Dm755 "$SCRIPT_DIR/lenovo-max-fan" /usr/local/sbin/lenovo-max-fan
install -Dm644 "$SCRIPT_DIR/lenovo-max-fan.service" \
    /etc/systemd/system/lenovo-max-fan.service
systemctl daemon-reload

printf '%s\n' \
    'Installed lenovo-max-fan.' \
    'The service was not enabled or started.' \
    'Review the hardware warning before starting it manually.'
