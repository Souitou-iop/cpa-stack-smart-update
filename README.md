# CPA Stack Smart Update

[![English](https://img.shields.io/badge/Language-English-blue)](./README.md)
[![简体中文](https://img.shields.io/badge/语言-简体中文-green)](./README.zh-CN.md)

A small BusyBox-compatible update script for a Docker Compose stack that runs:

- [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)
- [CPA Manager](https://github.com/seakee/CPA-Manager)

The script compares the version currently running on your router/server with the latest GitHub release. It updates a service only when the upstream release is newer.

## What It Does

For each service, the script:

1. Reads the local running version.
2. Fetches the latest release tag from GitHub.
3. Skips the service if the local version is equal to or newer than upstream.
4. Pulls the configured Docker image and recreates only that service when an update is available.

Default projects and images:

| Service | GitHub release source | Docker image |
| --- | --- | --- |
| `cli-proxy-api` | `router-for-me/CLIProxyAPI` | `eceasy/cli-proxy-api:latest` |
| `cpa-manager` | `seakee/CPA-Manager` | `seakee/cpa-manager:latest` |

## Requirements

- A Linux/OpenWrt-like shell environment with BusyBox `sh`.
- Docker and Docker Compose plugin available as `docker compose`.
- `curl`, `sed`, `grep`, `awk`, `sort`, and `date`.
- A Compose stack directory, defaulting to `/root/cpa-deploy`.
- Running containers named `cli-proxy-api` and `cpa-manager`.

The script expects this Compose service layout:

```yaml
services:
  cli-proxy-api:
    image: eceasy/cli-proxy-api:latest
    container_name: cli-proxy-api

  cpa-manager:
    image: seakee/cpa-manager:latest
    container_name: cpa-manager
```

## Install & Update

```sh
curl -fsSL https://raw.githubusercontent.com/Souitou-iop/cpa-stack-smart-update/main/install.sh | sh
```

The script will guide you through: language selection → local or remote install → detect existing installation → install or update → auto-verify.

Shortcut: append `user@host` to skip the mode selection, or `--local` to install on the current machine. Append a second argument to set a custom stack directory (default `/root/cpa-deploy`).

## Verify After Updating

One command to check everything — Compose status, CLIProxyAPI endpoints, and CPA Manager endpoints:

```sh
sh /root/cpa-deploy/update-cpa-stack.sh --verify
```

## Configuration

You can override the default stack directory, images, or upstream release repositories with environment variables:

```sh
STACK_DIR=/opt/cpa-deploy \
CLI_IMAGE=your-registry/cli-proxy-api:latest \
CLI_REPO=router-for-me/CLIProxyAPI \
MGR_IMAGE=your-registry/cpa-manager:latest \
MGR_REPO=seakee/CPA-Manager \
sh ./update-cpa-stack.sh --check-only
```

Variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `STACK_DIR` | `/root/cpa-deploy` | Directory containing `docker-compose.yml`. |
| `CLI_IMAGE` | `eceasy/cli-proxy-api:latest` | Image used for the `cli-proxy-api` service. |
| `CLI_REPO` | `router-for-me/CLIProxyAPI` | GitHub repo used to read the latest CLIProxyAPI release. |
| `MGR_IMAGE` | `seakee/cpa-manager:latest` | Image used for the `cpa-manager` service. |
| `MGR_REPO` | `seakee/CPA-Manager` | GitHub repo used to read the latest CPA Manager release. |

## Version Detection

CLIProxyAPI local version is read from recent container logs, for example:

```text
CLIProxyAPI Version: v7.1.44, Commit: fd30944, BuiltAt: 2026-06-03T17:06:42Z
```

CPA Manager local version is read from the running image OCI label:

```sh
docker image inspect "$(docker inspect -f '{{.Image}}' cpa-manager)" \
  --format '{{index .Config.Labels "org.opencontainers.image.version"}}'
```

## Safety Notes

- The first Compose edit is backed up as `docker-compose.yml.bak-smart-update-YYYYmmddHHMMSS`.
- The backup marker `.update-compose-backed-up` prevents repeated backup churn.
- The script updates only `cli-proxy-api` and `cpa-manager`.
- It does not update Home Assistant or other services.
- It depends on GitHub Release API availability.
- It uses version sorting, so release tags should be normal semantic versions such as `v7.1.44` or `1.5.5`.

## Troubleshooting

If version lookup fails:

```sh
docker logs --tail 50 cli-proxy-api
docker inspect cpa-manager
curl -fsSL https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest
curl -fsSL https://api.github.com/repos/seakee/CPA-Manager/releases/latest
```

If Docker Compose fails:

```sh
cd /root/cpa-deploy
docker compose config
docker compose ps
```

If your Compose directory is different:

```sh
STACK_DIR=/your/stack/path sh /path/to/update-cpa-stack.sh --check-only
```

## License

MIT
