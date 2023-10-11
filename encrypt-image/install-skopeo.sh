#!/bin/bash

set -euo pipefail
# Check if the DEBUG env var is set to true
if [ "${DEBUG:-false}" = "true" ]; then
    set -x
fi

# Check if skopeo is already installed then skip this script
if command -v skopeo >/dev/null 2>&1; then
    echo "skopeo is already installed, skipping..."
    exit 0
fi

export SKOPEO_VERSION=v1.13.3

sudo apt update &&
    sudo apt install -y \
        libdevmapper-dev \
        libgpgme-dev

cd $(mktemp -d)
git clone https://github.com/containers/skopeo
cd skopeo
git checkout $SKOPEO_VERSION
make bin/skopeo
cp bin/skopeo $GOBIN/skopeo
