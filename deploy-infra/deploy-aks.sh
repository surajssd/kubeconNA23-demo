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

AZURE_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
AKS_WORKER_USER_NAME="azuser"
AKS_RG="${AZURE_RESOURCE_GROUP}-aks"
AZURE_WORKLOAD_IDENTITY_NAME="caa-identity"

echo "Creating Resource Group: ${AZURE_RESOURCE_GROUP} in region: ${AZURE_REGION}..."
az group create --name "${AZURE_RESOURCE_GROUP}" \
    --location "${AZURE_REGION}"

# Create AKS only if it does not exists
if ! az aks show --resource-group "${AZURE_RESOURCE_GROUP}" --name "${CLUSTER_NAME}" >/dev/null 2>&1; then
    echo "Creating AKS cluster: ${CLUSTER_NAME}..."
    az aks create \
        --resource-group "${AZURE_RESOURCE_GROUP}" \
        --node-resource-group "${AKS_RG}" \
        --name "${CLUSTER_NAME}" \
        --location "${AZURE_REGION}" \
        --node-count 1 \
        --nodepool-labels node.kubernetes.io/worker= \
        --node-vm-size Standard_F4s_v2 \
        --ssh-key-value "${SSH_KEY}" \
        --admin-username "${AKS_WORKER_USER_NAME}" \
        --enable-addons http_application_routing \
        --enable-oidc-issuer \
        --enable-workload-identity \
        --os-sku Ubuntu
fi

echo "Getting AKS credentials..."
az aks get-credentials \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    --overwrite-existing

export CLUSTER_SPECIFIC_DNS_ZONE=$(az aks show \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    --query addonProfiles.httpApplicationRouting.config.HTTPApplicationRoutingZoneName -otsv)

echo "Creating Azure Identity: ${AZURE_WORKLOAD_IDENTITY_NAME}..."
az identity create \
    --name "${AZURE_WORKLOAD_IDENTITY_NAME}" \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --location "${AZURE_REGION}"

export AKS_OIDC_ISSUER="$(az aks show \
    --name "$CLUSTER_NAME" \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --query "oidcIssuerProfile.issuerUrl" \
    -otsv)"

az identity federated-credential create \
    --name caa-fedcred \
    --identity-name $AZURE_WORKLOAD_IDENTITY_NAME \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --issuer "${AKS_OIDC_ISSUER}" \
    --subject system:serviceaccount:confidential-containers-system:cloud-api-adaptor \
    --audience api://AzureADTokenExchange

export USER_ASSIGNED_CLIENT_ID="$(az identity show \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --name "${AZURE_WORKLOAD_IDENTITY_NAME}" \
    --query 'clientId' \
    -otsv)"

for i in {1..10}; do
    if az ad sp show \
        --id "${USER_ASSIGNED_CLIENT_ID}" >/dev/null 2>&1; then
        break
    fi
    echo "Waiting for service principal to be created..."
    sleep 5
done

az role assignment create \
    --role 'Virtual Machine Contributor' \
    --assignee "$USER_ASSIGNED_CLIENT_ID" \
    --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourcegroups/${AZURE_RESOURCE_GROUP}"

az role assignment create \
    --role 'Reader' \
    --assignee "$USER_ASSIGNED_CLIENT_ID" \
    --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourcegroups/${AZURE_RESOURCE_GROUP}"

az role assignment create \
    --role 'Network Contributor' \
    --assignee "$USER_ASSIGNED_CLIENT_ID" \
    --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourcegroups/${AKS_RG}"

echo "Run the following command before deploying KBS:"
echo "export CLUSTER_SPECIFIC_DNS_ZONE=${CLUSTER_SPECIFIC_DNS_ZONE}"
