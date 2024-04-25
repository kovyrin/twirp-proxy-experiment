#!/usr/bin/env bash

set -exo pipefail

CONFIG_DIR=$(dirname $0)
CONFIG_FILE="${CONFIG_DIR}/default.vcl"
ABS_CONFIG_FILE=$(realpath "${CONFIG_FILE}")

/opt/homebrew/opt/varnish/sbin/varnishd \
    -n /opt/homebrew/var/varnish \
    -f "${ABS_CONFIG_FILE}" \
    -s malloc,1G \
    -T 127.0.0.1:2000 \
    -a 127.0.0.1:3002 \
    -F
