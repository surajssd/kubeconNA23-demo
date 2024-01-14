# Deploying Encrypted Container Images with Cloud API Adaptor

## Encrypt Image

### Generate Image Encryption / Decryption Symmetric Key

```bash
export KEY_FILE="$(pwd)/key.bin"
# NOTE: Key needs to be 32 bytes.
head -c 32 /dev/urandom | openssl enc >"$KEY_FILE"
```

### Encrypt Image

Here we will use an existing `busybox` image, encrypt it with the previously created key and upload it to a new destination.

```bash
export QUAY_USERID=REPLACE_ME
export SOURCE_IMAGE=busybox
export DESTINATION_IMAGE=quay.io/${QUAY_USERID}/busybox-encrypted:$(date '+%Y-%m-%b-%d-%H-%M-%S')
export KEY_ID="default/image-decryption-keys/key.bin"
make encrypt-image
```

## Deploy Infrastructure

### Deploy AKS

```bash
export AZURE_RESOURCE_GROUP=REPLACE_ME
export SSH_KEY=REPLACE_ME
make deploy-aks
```

Based on the output of the above command run:

```bash
export CLUSTER_SPECIFIC_DNS_ZONE=REPLACE_ME
```


### Deploy KBS with Image Encryption / Decryption Symmetric Key

```bash
make deploy-kbs
```

### Deploy CAA

```bash
make deploy-caa
```

## Deploy Application with Encrypted Image

```bash
make deploy-encrypted-app
```
