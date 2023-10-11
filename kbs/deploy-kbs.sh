#!/bin/bash

set -euo pipefail
# Check if the DEBUG env var is set to true
if [ "${DEBUG:-false}" = "true" ]; then
    set -x
fi

# Compulsory env vars
: "${KEY_FILE}:?"
: "${CLUSTER_SPECIFIC_DNS_ZONE}:?"

# Ensure we always clone the kbs code base in the kbs sub directory.
cd $(dirname "$0")

# Pull the KBS code base if it is not available
if [ ! -d kbs ]; then
    git clone https://github.com/surajssd/kbs -b k8s-deploy-ingress-install
fi

pushd kbs/config/kubernetes

# Set the image to use the latest bits from the KBS repository.
pushd base
kustomize edit set image kbs-container-image=quay.io/surajd/kbs:latest
popd

pushd overlays

cp ${KEY_FILE} key.bin

# Add the Image Encryption / Decryption Symmetric Key
echo "
- op: add
  path: /spec/template/spec/containers/0/volumeMounts/-
  value:
    name: image-decryption-key
    mountPath: /opt/confidential-containers/kbs/repository/default/image-decryption-keys/
- op: add
  path: /spec/template/spec/volumes/-
  value:
    name: image-decryption-key
    secret:
      secretName: image-decryption-key
" | tee patch.yaml

echo "
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: coco-tenant

resources:
- ../base

patches:
- path: patch.yaml
  target:
    group: apps
    kind: Deployment
    name: kbs
    version: v1

secretGenerator:
- files:
  - key.bin
  name: image-decryption-key
" | tee kustomization.yaml

# Enable Ingress
export KBS_INGRESS_CLASS="addon-http-application-routing"
export KBS_INGRESS_HOST="kbs.${CLUSTER_SPECIFIC_DNS_ZONE}"

envsubst <ingress.yaml >ingress.yaml.tmp && mv ingress.yaml.tmp ingress.yaml
kustomize edit add resource ingress.yaml
popd

./deploy-kbs.sh
