.PHONY: build-coco-key-provider
build-coco-key-provider:
	./coco-key-provider/build-push.sh

.PHONY: install-skopeo
install-skopeo:
	./encrypt-image/install-skopeo.sh

.PHONY: encrypt-image
encrypt-image: install-skopeo
	./encrypt-image/encrypt-image.sh

.PHONY: deploy-kbs
deploy-kbs:
	./kbs/deploy-kbs.sh

.PHONY: deploy-encrypted-app
deploy-encrypted-app:
	# Check if the env var DESTINATION_IMAGE is exported
ifndef DESTINATION_IMAGE
	$(error DESTINATION_IMAGE is not set)
endif
	envsubst <encrypted-app/deployment.yaml | kubectl apply -f -
