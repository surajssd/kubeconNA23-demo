# Deploying Encrypted Container Images with Cloud API Adatpor

## Encrypt Image

### Generate Image Encryption / Decryption Symmetric Key

```bash
export KEY_FILE="$(pwd)/key.bin"
head -c 32 /dev/urandom | openssl enc >"$KEY_FILE"
```

### Encrypt Image

Here we will use an existing `busybox` image encrypt it with the previously created key and upload it to a new destination.

```bash
export SOURCE_IMAGE=busybox
export DESTINATION_IMAGE=quay.io/surajd/busybox-encrypted:$(date '+%Y-%m-%b-%d-%H-%M-%S')
export KEY_ID="default/image-decryption-keys/key.bin"
make encrypt-image
```

## Deploy KBS

### Deploy KBS with Image Encryption / Decryption Symmetric Key

```bash
echo export CLUSTER_SPECIFIC_DNS_ZONE=$(az aks show \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    --query addonProfiles.httpApplicationRouting.config.HTTPApplicationRoutingZoneName -otsv)

make deploy-kbs
```

## Deploy Application with Encrypted Image

```bash
make deploy-encrypted-app
```
