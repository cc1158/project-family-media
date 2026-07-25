APP_NAME := family-media-server
CONFIG ?= configs/config.yaml
VERSION ?= local
BUILD_TIME ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
GIT_COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
ifneq ($(shell git status --porcelain 2>/dev/null),)
GIT_COMMIT := $(GIT_COMMIT)-dirty
endif
LDFLAGS := -s -w \
	-X family-media-server/internal/platform/buildinfo.Version=$(VERSION) \
	-X family-media-server/internal/platform/buildinfo.Commit=$(GIT_COMMIT) \
	-X family-media-server/internal/platform/buildinfo.BuiltAt=$(BUILD_TIME)
NAS_PLATFORM ?= linux/amd64
GOPROXY ?= https://proxy.golang.org,direct
DOCKER_TAG_ARGS := -t $(APP_NAME):local $(if $(filter local,$(VERSION)),,-t $(APP_NAME):$(VERSION))
EXPORT_IMAGE := $(if $(filter local,$(VERSION)),$(APP_NAME):local,$(APP_NAME):$(VERSION))
RELEASE_DIR := dist/releases/$(VERSION)

.PHONY: run test fmt build nas-binary docker-build docker-export check-release-version release-binary release-docker release clean

run:
	go run ./cmd/$(APP_NAME) -config $(CONFIG)

test:
	go test ./...

fmt:
	gofmt -w ./cmd ./internal

build:
	go build -ldflags "$(LDFLAGS)" -o ./bin/$(APP_NAME) ./cmd/$(APP_NAME)

nas-binary:
	mkdir -p ./dist
	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -o ./dist/$(APP_NAME) ./cmd/$(APP_NAME)
	chmod 755 ./dist/$(APP_NAME)
	cd ./dist && shasum -a 256 $(APP_NAME) > $(APP_NAME).sha256

docker-build:
	docker buildx build \
		--platform $(NAS_PLATFORM) \
		--build-arg GOPROXY=$(GOPROXY) \
		--build-arg VERSION=$(VERSION) \
		--build-arg BUILD_COMMIT=$(GIT_COMMIT) \
		--build-arg BUILD_TIME=$(BUILD_TIME) \
		-f deployments/docker/Dockerfile \
		$(DOCKER_TAG_ARGS) \
		--load \
		.

docker-export: docker-build
	docker save $(APP_NAME):local -o $(APP_NAME).tar
	shasum -a 256 $(APP_NAME).tar > $(APP_NAME).tar.sha256

check-release-version:
	@printf '%s\n' "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$$' || \
		(echo "VERSION must be a release version, for example 1.0.0-rc.1" >&2; exit 1)

release-binary: check-release-version nas-binary
	mkdir -p $(RELEASE_DIR)
	cp ./dist/$(APP_NAME) $(RELEASE_DIR)/$(APP_NAME)-linux-amd64
	cd $(RELEASE_DIR) && shasum -a 256 $(APP_NAME)-linux-amd64 > $(APP_NAME)-linux-amd64.sha256
	cp ./configs/config.nas.example.yaml $(RELEASE_DIR)/config.nas.example.yaml

release-docker: check-release-version docker-build
	mkdir -p $(RELEASE_DIR)
	docker save $(EXPORT_IMAGE) -o $(RELEASE_DIR)/$(APP_NAME)-$(VERSION)-linux-amd64.tar
	cd $(RELEASE_DIR) && shasum -a 256 $(APP_NAME)-$(VERSION)-linux-amd64.tar > $(APP_NAME)-$(VERSION)-linux-amd64.tar.sha256

release: release-binary release-docker

clean:
	rm -rf ./bin ./dist
