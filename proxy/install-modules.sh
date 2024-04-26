#!/usr/bin/env bash

set -exo pipefail

MODS_URL="https://github.com/varnish/varnish-modules/releases/download/0.24.0/varnish-modules-0.24.0.tar.gz"

mkdir -p /tmp/varnish-modules
cd /tmp/varnish-modules
curl -L -o varnish-modules.tar.gz "${MODS_URL}"
tar -xzf varnish-modules.tar.gz

cd varnish-modules-0.24.0
./configure
make
make install
