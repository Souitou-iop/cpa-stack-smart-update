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

## Where The Script Is

In this repository:

```text
update-cpa-stack.sh
```

Recommended install path on the router/server:

```text
/root/cpa-deploy/update-cpa-stack.sh
```

## Install

SSH into the router/server first:

```sh
ssh root@192.168.31.81
```

Download the script into the stack directory:

```sh
cd /root/cpa-deploy
curl -fsSLo update-cpa-stack.sh \
  https://raw.githubusercontent.com/Souitou-iop/cpa-stack-smart-update/main/update-cpa-stack.sh
chmod +x update-cpa-stack.sh
```

If your stack is not in `/root/cpa-deploy`, either put the script in your own stack directory or set `STACK_DIR` when running it.

## Check Only

Run a dry check first:

```sh
sh /root/cpa-deploy/update-cpa-stack.sh --check-only
```

Example output when nothing needs updating:

```text
[cli-proxy-api] local=v7.1.44 latest=v7.1.44
[cli-proxy-api] up-to-date, skip
[cpa-manager] local=1.5.5 latest=v1.5.5
[cpa-manager] up-to-date, skip
```

`--check-only` never runs `docker pull` and never recreates containers.

## Run The Update

```sh
sh /root/cpa-deploy/update-cpa-stack.sh
```

When a newer upstream release exists, the script runs the equivalent of:

```sh
docker pull eceasy/cli-proxy-api:latest
cd /root/cpa-deploy
docker compose up -d cli-proxy-api
```

or:

```sh
docker pull seakee/cpa-manager:latest
cd /root/cpa-deploy
docker compose up -d cpa-manager
```

Only the service that needs an update is recreated. Other services in the same Compose file are left alone.

## Verify After Updating

Check the Compose status:

```sh
cd /root/cpa-deploy
docker compose ps
```

Check CLIProxyAPI:

```sh
curl -sS http://127.0.0.1:8317/
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8317/v1/models
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8317/management.html
```

Expected results:

- `/` returns the API server response.
- `/v1/models` returns `401` without an API key.
- `/management.html` returns `200` when the management page is enabled.

Check CPA Manager:

```sh
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:18317/management.html
```

Expected result:

- `/management.html` returns `200`.

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
