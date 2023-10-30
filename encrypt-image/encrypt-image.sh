#!/bin/bash

set -euo pipefail
# Check if the DEBUG env var is set to true
if [ "${DEBUG:-false}" = "true" ]; then
    set -x
fi

# Compulsory env vars
: "${SOURCE_IMAGE}:?"
: "${DESTINATION_IMAGE}:?"
: "${KEY_ID}:?"

ARTIFACTS_DIR="${PWD}"
COCO_KEY_PROVIDER=${COCO_KEY_PROVIDER:-quay.io/surajd/coco-key-provider:88dcc14}
KEY_FILE=${KEY_FILE:-$ARTIFACTS_DIR/keyfile}

# Defaults
WORK_DIR="$(mktemp -d)"
KEYPROVIDER_PARAMS="provider:attestation-agent:keypath=/${KEY_FILE}::keyid=kbs:///${KEY_ID}::algorithm=A256GCM"
export OCICRYPT_KEYPROVIDER_CONFIG="${WORK_DIR}/ocicrypt.conf"

# Generate the keyfile if it doesn't exist
if [ ! -f "$KEY_FILE" ]; then
    echo "Generating keyfile at $KEY_FILE ..."
    head -c 32 /dev/urandom | openssl enc >"$KEY_FILE"
fi

echo '{"key-providers": {"attestation-agent": {"grpc": "localhost:50000"}}}' >$WORK_DIR/ocicrypt.conf

# Let's start the coco key provider as a background process
echo "Starting the coco-key-provider container on localhost:50000..."
docker run -d -p 50000:50000 -v "${KEY_FILE}:/${KEY_FILE}" --name coco-key-provider "${COCO_KEY_PROVIDER}"

# Run this command regardless of the success or failure of the skopeo command
trap 'echo "Removing the coco-key-provider container..."; docker rm -f coco-key-provider' EXIT

pushd "${WORK_DIR}"
skopeo copy \
    --insecure-policy \
    --encryption-key "${KEYPROVIDER_PARAMS}" \
    docker://${SOURCE_IMAGE} \
    "docker://${DESTINATION_IMAGE}"
popd

echo "Successfully encrypted image: ${SOURCE_IMAGE} to ${DESTINATION_IMAGE}"
echo "Store the key: ${KEY_FILE} at location: ${KEY_ID} in KBS."
