#!/bin/bash

set -euo pipefail
# Check if the DEBUG env var is set to true
if [ "${DEBUG:-false}" = "true" ]; then
    set -x
fi

# Last release of the confidential-containers guest-components repository.
export GUEST_COMPONENTS_COMMIT=88dcc14

# Use the image name provided by the user or use the default one.
IMAGE_NAME="${IMAGE_NAME:-quay.io/surajd/coco-key-provider:$GUEST_COMPONENTS_COMMIT}"

docker build \
    --push \
    -t "${IMAGE_NAME}" \
    $(dirname "$0") # Doesn't matter where this is invoked from, change dir into this script's directory.

echo "Successfully built and pushed image: ${IMAGE_NAME}"
