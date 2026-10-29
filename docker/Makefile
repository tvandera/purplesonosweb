QEMU ?= qemu-system-i386
QEMU_IMG ?= qemu-img
ISO ?= android-x86-4.4-r5.iso
DISK ?= android-4.4.qcow2
ISO_URL ?= https://sourceforge.net/projects/android-x86/files/Release%204.4/android-x86-4.4-r5.iso/download
VNC ?= :1
MEMORY ?= 2048
CPUS ?= 2
DISK_SIZE ?= 8G
PROXY_IP ?=
PROXY_PORT ?=
ANDROID_44_USER_AGENT ?= Mozilla/5.0 (Linux; Android 4.4.4; Nexus 5 Build/KTU84P) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/30.0.0.0 Mobile Safari/537.36
LEGACY_BROWSER_IMAGE ?= sonos-legacy-browser
LEGACY_BROWSER_NAME ?= sonos-legacy-browser
LEGACY_BROWSER_VNC_PORT ?= 5901
LEGACY_BROWSER_VNC_PASSWORD ?= sonos
LEGACY_BROWSER_URL ?= http://192.168.2.13:9999

SONOS_IMAGE ?= purplesonosweb
SONOS_TAG ?= latest
# linux/arm64 for Pi 3/4/5 on 64-bit OS; use linux/arm/v7 for 32-bit Raspberry Pi OS
PI_PLATFORM ?= linux/arm64
SONOS_TAR ?= $(SONOS_IMAGE)-pi.tar
SONOS_REGISTRY_IMAGE ?= ghcr.io/tvandera/purplesonosweb

.DEFAULT_GOAL := install
.PHONY: install run start-sonos-web start-legacy-browser connect connect-legacy-browser stop-legacy-browser build build-pi save-pi run-pi push

# Builds for the local machine's architecture.
build:
	docker build --file Dockerfile --tag $(SONOS_IMAGE):$(SONOS_TAG) ../perl

# Needs docker buildx (and qemu binfmt emulation when not building on arm).
build-pi:
	docker buildx build --platform $(PI_PLATFORM) --file Dockerfile \
		--tag $(SONOS_IMAGE):$(SONOS_TAG) --load ../perl

# Requires `docker login ghcr.io` with a token that has write:packages.
push:
	docker buildx build --platform $(PI_PLATFORM) --file Dockerfile \
		--tag $(SONOS_REGISTRY_IMAGE):$(SONOS_TAG) --push ../perl

save-pi: build-pi
	docker save --output $(SONOS_TAR) $(SONOS_IMAGE):$(SONOS_TAG)

# Run on the Pi itself; host networking is required for Sonos discovery.
run-pi:
	docker run --rm --network host $(SONOS_IMAGE):$(SONOS_TAG)

start-sonos-web:
	docker-compose up --build --detach

start-legacy-browser:
	docker build --platform linux/amd64 --file Dockerfile.legacy-browser --tag $(LEGACY_BROWSER_IMAGE) .
	-docker rm --force $(LEGACY_BROWSER_NAME)
	docker run --detach --name $(LEGACY_BROWSER_NAME) --platform linux/amd64 \
		--publish 127.0.0.1:$(LEGACY_BROWSER_VNC_PORT):5900 \
		--env TEST_URL="$(LEGACY_BROWSER_URL)" \
		--env ANDROID_44_USER_AGENT="$(ANDROID_44_USER_AGENT)" \
		--env VNC_PASSWORD="$(LEGACY_BROWSER_VNC_PASSWORD)" \
		$(LEGACY_BROWSER_IMAGE)
	@attempt=0; \
	until [ "$$(docker inspect --format='{{.State.Health.Status}}' $(LEGACY_BROWSER_NAME) 2>/dev/null)" = healthy ]; do \
		attempt=$$((attempt + 1)); \
		if [ $$attempt -ge 30 ]; then docker logs $(LEGACY_BROWSER_NAME); exit 1; fi; \
		sleep 1; \
	done

connect: connect-legacy-browser

connect-legacy-browser:
	open "vnc://localhost:$(LEGACY_BROWSER_VNC_PORT)"

stop-legacy-browser:
	docker rm --force $(LEGACY_BROWSER_NAME)

$(ISO):
	curl --location --fail --output "$@" "$(ISO_URL)"

$(DISK):
	$(QEMU_IMG) create -f qcow2 "$@" $(DISK_SIZE)

install: $(ISO) $(DISK)
	$(QEMU) \
		-name android-4.4 \
		-m $(MEMORY) -smp $(CPUS) \
		-vga std \
		-netdev user,id=net0 -device e1000,netdev=net0 \
		-drive file="$(DISK)",format=qcow2,if=ide \
		-cdrom "$(ISO)" -boot order=d \
		-vnc $(VNC)

run: $(DISK)
	$(QEMU) \
		-name android-4.4 \
		-m $(MEMORY) -smp $(CPUS) \
		-vga std \
		-netdev user,id=net0 -device e1000,netdev=net0 \
		-drive file="$(DISK)",format=qcow2,if=ide \
		-boot order=c \
		-vnc $(VNC)