# Docker

Production container for the Sonos web app (`perl/scripts/sonod`, port 9999), plus a legacy-browser test VM.

## Setup

`nix develop` (or direnv) in this directory provides `docker`, `docker-compose`, `gh`, `make` and `qemu`.

Building for a Raspberry Pi from a non-ARM machine needs `docker buildx` with QEMU/binfmt emulation.

## Files

- `Dockerfile`: multi-stage production image, built with `../perl/` as its context.
- `Dockerfile.dockerignore`: keeps build output and tests out of the image context.
- `docker-compose.yml`: builds and runs the image with host networking.

## Make targets

| Target | Description |
| --- | --- |
| `make build` | Build `purplesonosweb:latest` for the local machine's architecture |
| `make build-pi` | Build `purplesonosweb:latest` for `PI_PLATFORM` and load it locally |
| `make save-pi` | Build, then write `purplesonosweb-pi.tar` for `docker load` on the Pi |
| `make run-pi` | Run the image with `--network host` |
| `make push` | Build and push to `ghcr.io/tvandera/purplesonosweb` |

Variables:

- `PI_PLATFORM`: `linux/arm64` by default (Pi 3/4/5 on a 64-bit OS). Use `linux/arm/v7` for 32-bit Raspberry Pi OS.
- `SONOS_TAG`: image tag, `latest` by default.
- `SONOS_REGISTRY_IMAGE`: registry image name used by `push`.

## Running

Sonos discovery uses SSDP multicast, so the container must use host networking. The web UI is then at `http://<host>:9999`.

```sh
docker compose up -d      # build and run from source
make run-pi               # run a built image
```

On the Pi, pull the pushed image instead of building:

```sh
docker run -d --network host --restart unless-stopped ghcr.io/tvandera/purplesonosweb:latest
```

The JSON and album-art caches are not stored in a volume, so they are lost when the container is removed.

## Pushing to GitHub Container Registry

Log in with the GitHub CLI instead of a personal access token:

```sh
gh auth login --scopes write:packages    # or: gh auth refresh -s write:packages
gh auth token | docker login ghcr.io -u tvandera --password-stdin
make push
```

## Legacy browser (Android 4.4)

`make install` and `make run` boot an Android x86 4.4 VM under QEMU. `make start-legacy-browser` and `make stop-legacy-browser` run a containerised legacy browser for testing the UI.
