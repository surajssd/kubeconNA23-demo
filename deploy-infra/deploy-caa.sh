#!/bin/bash

set -euo pipefail
# Check if the DEBUG env var is set to true
if [ "${DEBUG:-false}" = "true" ]; then
  set -x
fi

# Compulsory env vars
: "${AZURE_RESOURCE_GROUP}:?"
: "${SSH_KEY}:?"

AZURE_REGION=${AZURE_REGION:-eastus}
CLUSTER_NAME="${CLUSTER_NAME:-caaEncryptedImages}"

CAA_IMAGE="${CAA_IMAGE:-quay.io/confidential-containers/cloud-api-adaptor}"
CAA_TAG="${CAA_TAG:-d4496d008b65c979a4d24767979a77ed1ba21e76}"
CAA_VERSION="${CAA_VERSION:-0.8.0}"

AZURE_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
AKS_RG="${AZURE_RESOURCE_GROUP}-aks"
registry="quay.io/confidential-containers"
# This is calculated as: /CommunityGalleries/cocopodvm-d0e4f35f-5530-4b9c-8596-112487cdea85/Images/podvm_image0/Versions/$(date -v -1d "+%Y.%m.%d" 2>/dev/null || date -d "yesterday" "+%Y.%m.%d")
AZURE_IMAGE_ID="/CommunityGalleries/cococommunity-42d8482d-92cd-415b-b332-7648bd978eff/Images/peerpod-podvm-ubuntu2204-cvm-snp/Versions/${CAA_VERSION}"
AZURE_WORKLOAD_IDENTITY_NAME="caa-identity"

export USER_ASSIGNED_CLIENT_ID="$(az identity show \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --name "${AZURE_WORKLOAD_IDENTITY_NAME}" \
  --query 'clientId' \
  -otsv)"

export AZURE_VNET_NAME=$(az network vnet list \
  --resource-group "${AKS_RG}" \
  --query "[0].name" \
  --output tsv)

export AZURE_SUBNET_ID=$(az network vnet subnet list \
  --resource-group "${AKS_RG}" \
  --vnet-name "${AZURE_VNET_NAME}" \
  --query "[0].id" \
  --output tsv)

export CLUSTER_SPECIFIC_DNS_ZONE=$(az aks show \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --name "${CLUSTER_NAME}" \
  --query addonProfiles.httpApplicationRouting.config.HTTPApplicationRoutingZoneName -otsv)

# Ensure we always clone the kbs code base in the kbs sub directory.
cd $(dirname "$0")

# Pull the CAA code
if [ ! -d cloud-api-adaptor ]; then
  git clone https://github.com/confidential-containers/cloud-api-adaptor
  pushd cloud-api-adaptor
  git checkout "v${CAA_VERSION}"
  popd
fi

pushd cloud-api-adaptor

cat <<EOF >install/overlays/azure/workload-identity.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: cloud-api-adaptor-daemonset
  namespace: confidential-containers-system
spec:
  template:
    metadata:
      labels:
        azure.workload.identity/use: "true"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cloud-api-adaptor
  namespace: confidential-containers-system
  annotations:
    azure.workload.identity/client-id: "$USER_ASSIGNED_CLIENT_ID"
EOF

cat <<EOF >install/overlays/azure/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
- ../../yamls
images:
- name: cloud-api-adaptor
  newName: "${CAA_IMAGE}"
  newTag: "${CAA_TAG}"
generatorOptions:
  disableNameSuffixHash: true
configMapGenerator:
- name: peer-pods-cm
  namespace: confidential-containers-system
  literals:
  - CLOUD_PROVIDER="azure"
  - AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
  - AZURE_REGION="${AZURE_REGION}"
  - AZURE_INSTANCE_SIZE="Standard_DC2as_v5"
  - AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP}"
  - AZURE_SUBNET_ID="${AZURE_SUBNET_ID}"
  - AZURE_IMAGE_ID="${AZURE_IMAGE_ID}"
  - AA_KBC_PARAMS="cc_kbc::http://kbs.${CLUSTER_SPECIFIC_DNS_ZONE}"
secretGenerator:
- name: peer-pods-secret
  namespace: confidential-containers-system
- name: ssh-key-secret
  namespace: confidential-containers-system
  files:
  - id_rsa.pub
patchesStrategicMerge:
- workload-identity.yaml
EOF

cp $SSH_KEY install/overlays/azure/id_rsa.pub
export CLOUD_PROVIDER=azure

# Install operator
kubectl apply -k "github.com/confidential-containers/operator/config/release?ref=v0.8.0"
kubectl apply -k "github.com/confidential-containers/operator/config/samples/ccruntime/peer-pods?ref=v0.8.0"
kubectl apply -k "install/overlays/${CLOUD_PROVIDER}"

# Wait until the runtimeclass is created
for i in {1..20}; do
  if kubectl get runtimeclass kata-remote >/dev/null 2>&1; then
    break
  fi

  echo "Waiting for runtimeclass to be created..."
  sleep 6
done
