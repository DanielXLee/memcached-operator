.DEFAULT_GOAL:=help
SHELL:=/bin/bash
NAMESPACE=memcached
VERSION=2.1.0
CSV_VERSION=${VERSION}
IMAGE_VERSION=${VERSION}
IMAGE_REPO ?= quay.io/danielxlee
IMAGE_NAME ?= memcached-operator-img

##@ Application

install: ## Install all resources (CR/CRD's, RBAC and Operator)
	@echo ....... Creating namespace ....... 
	- kubectl create namespace ${NAMESPACE}
	@echo ....... Applying CRDs .......
	- kubectl apply -f deploy/crds/cache.test.com_memcacheds_crd.yaml -n ${NAMESPACE}
	@echo ....... Applying Rules and Service Account .......
	- kubectl apply -f deploy/role.yaml -n ${NAMESPACE}
	- kubectl apply -f deploy/role_binding.yaml  -n ${NAMESPACE}
	- kubectl apply -f deploy/service_account.yaml  -n ${NAMESPACE}
	@echo ....... Applying Operator .......
	- kubectl apply -f deploy/operator.yaml -n ${NAMESPACE}
	@echo ....... Creating the CRs .......
	- kubectl apply -f deploy/crds/cache.test.com_v1alpha1_memcached_cr.yaml -n ${NAMESPACE}

uninstall: ## Uninstall all that all performed in the $ make install
	@echo ....... Uninstalling .......
	@echo ....... Deleting CRDs.......
	- kubectl delete -f deploy/crds/cache.test.com_memcacheds_crd.yaml -n ${NAMESPACE}
	@echo ....... Deleting Rules and Service Account .......
	- kubectl delete -f deploy/role.yaml -n ${NAMESPACE}
	- kubectl delete -f deploy/role_binding.yaml -n ${NAMESPACE}
	- kubectl delete -f deploy/service_account.yaml -n ${NAMESPACE}
	@echo ....... Deleting Operator .......
	- kubectl delete -f deploy/operator.yaml -n ${NAMESPACE}
	@echo ....... Deleting namespace ${NAMESPACE}.......
	- kubectl delete namespace ${NAMESPACE}

##@ Development

code-vet: ## Run go vet for this project. More info: https://golang.org/cmd/vet/
	@echo go vet
	go vet $$(go list ./... )

code-fmt: ## Run go fmt for this project
	@echo go fmt
	go fmt $$(go list ./... )


code-tidy: ## Run go mod tidy to update dependencies
	@echo go mod tidy
	go mod tidy -v

code-gen-bundle: ## Run operator-sdk bundle create to create metadata
	operator-sdk bundle create \
		--generate-only \
		--directory ./deploy/olm-catalog/memcached-operator/${CSV_VERSION} \
		--package memcached-operator \
		--channels alpha,beta \
		--default-channel alpha

code-gen: ## Run the operator-sdk commands to generated code (k8s and openapi)
	@echo Updating the deep copy files with the changes in the API
	operator-sdk generate k8s
	@echo Updating the CRD files with the OpenAPI validations
	operator-sdk generate crds
	@echo Updating/Generating a ClusterServiceVersion YAML manifest for the operator
	operator-sdk generate csv --make-manifests=false --csv-version ${CSV_VERSION} --update-crds
	operator-sdk generate csv --csv-version ${CSV_VERSION}

code-dev: ## Run the default dev commands which are the go fmt and vet then execute the $ make code-gen
	@echo Running the common required commands for developments purposes
	- make code-tidy
	- make code-fmt
	- make code-vet
	- make code-gen

##@ Tests

test-e2e: ## Run integration e2e tests with different options.
	@echo ... Running the same e2e tests with different args ...
	@echo ... Running locally ...
	- kubectl create namespace ${NAMESPACE} || true
	- operator-sdk test local ./test/e2e --up-local --namespace=${NAMESPACE}
	@echo ... Running NOT in parallel ...
	- operator-sdk test local ./test/e2e --go-test-flags "-v -parallel=1"
	@echo ... Running in parallel ...
	- operator-sdk test local ./test/e2e --go-test-flags "-v -parallel=2"
	@echo ... Running without options/args ...
	- operator-sdk test local ./test/e2e
	@echo ... Running with the --debug param ...
	- operator-sdk test local ./test/e2e --debug
	@echo ... Running with the --verbose param ...
	- operator-sdk test local ./test/e2e --verbose

##@ Publish
image: ## Build image
	operator-sdk build ${IMAGE_REPO}/${IMAGE_NAME}:${IMAGE_VERSION}

push: image ## Push image to registry
	docker push ${IMAGE_REPO}/${IMAGE_NAME}:${IMAGE_VERSION}

push-csv: ## Push CSV package to the catalog
	@RELEASE=${CSV_VERSION} common/scripts/push-csv.sh

bundle-image: ## Create operator bundle image
	@echo "Bulding the operator bundle image"
	- operator-sdk bundle create quay.io/danielxlee/memcached-operator-bundle:v${CSV_VERSION} \
		--directory ./deploy/olm-catalog/memcached-operator/manifests \
		--package memcached-operator \
		--channels alpha,beta \
		--default-channel alpha

.PHONY: help
help: ## Display this help
	@echo -e "Usage:\n  make \033[36m<target>\033[0m"
	@awk 'BEGIN {FS = ":.*##"}; \
		/^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
