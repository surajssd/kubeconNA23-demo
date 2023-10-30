#!/bin/bash

set -euo pipefail
# Check if the DEBUG env var is set to true
if [ "${DEBUG:-false}" = "true" ]; then
    set -x
fi

# Check if skopeo is already installed then skip this script
if command -v skopeo >/dev/null 2>&1; then
    # # Sample output of skopeo --version
    # $ skopeo --version
    # skopeo version 1.13.3 commit: 9e29e4cede9bdaa4a54aa5b0af86efedb823bde4
    skopeo_minor=$(skopeo --version | awk '{print $3}' | cut -d'.' -f2)
    if [ "$skopeo_minor" -ge 13 ]; then
        echo "skopeo is already installed, skipping..."
        exit 0
    fi
    echo "skopeo version > 1.13.x needed! Please uninstall the existing skopeo and re-run this script. Current version: $(skopeo --version)."
    exit 1
fi

# Compulsory env vars
: "${GOBIN}:?"

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
