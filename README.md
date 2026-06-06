# CPA Stack Smart Update

[![English](https://img.shields.io/badge/Language-English-blue)](./README.md)
[![简体中文](https://img.shields.io/badge/语言-简体中文-green)](./README.zh-CN.md)

Automatically detect and update CLIProxyAPI and CPA Manager in your Docker Compose stack. Only updates when a new version is available, leaves other services untouched.

## Quick Start

Run this command on your computer:

```sh
curl -fsSL https://raw.githubusercontent.com/Souitou-iop/cpa-stack-smart-update/main/install.sh -o /tmp/install-cpa.sh && sh /tmp/install-cpa.sh
```

The script will guide you through: language → remote or local install → detect → install or update → verify.

How it works:
- **Script updates** (update-cpa-stack.sh): automatically updates when a new version is found, no confirmation needed
- **Service updates** (CLIProxyAPI / CPA Manager): asks for user confirmation before updating

Shortcuts:
- Remote install: `sh /tmp/install-cpa.sh root@192.168.1.1`
- Local install: `sh /tmp/install-cpa.sh --local`
- Custom directory: `sh /tmp/install-cpa.sh root@192.168.1.1 /opt/cpa-deploy`

## What Does This Do?

In simple terms: automatically updates two Docker services on your router/server.

```
Check version → New version? → Pull image → Recreate container → Verify
                    ↓ No
                  Skip
```

Default services updated:

| Service | Image | Purpose |
| --- | --- | --- |
| CLIProxyAPI | `eceasy/cli-proxy-api:latest` | API proxy service |
| CPA Manager | `seakee/cpa-manager:latest` | Management panel |

## One-Command Verify

After updating, check everything with one command:

```sh
sh /root/cpa-deploy/update-cpa-stack.sh --verify
```

Automatically checks: container status + CLIProxyAPI endpoints + CPA Manager endpoints.

## Requirements

- Docker installed on your router/server
- SSH access (for remote install)
- GitHub access (for checking updates and downloading scripts)

## Safety

- Auto-backs up `docker-compose.yml` before any changes
- Only updates CLIProxyAPI and CPA Manager, ignores other services
- Asks for confirmation before updating each service
- Version comparison based on GitHub Release tags

## Automated Updates (Cron)

For scheduled automatic updates, use `--yes` to skip confirmation:

```sh
sh /root/cpa-deploy/update-cpa-stack.sh --yes
```

## Configuration

If your stack directory is not the default `/root/cpa-deploy`, or you need custom images:

```sh
STACK_DIR=/opt/cpa-deploy \
CLI_IMAGE=your-registry/cli-proxy-api:latest \
MGR_IMAGE=your-registry/cpa-manager:latest \
sh /root/cpa-deploy/update-cpa-stack.sh --check-only
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `STACK_DIR` | `/root/cpa-deploy` | Stack directory |
| `CLI_IMAGE` | `eceasy/cli-proxy-api:latest` | CLIProxyAPI image |
| `CLI_REPO` | `router-for-me/CLIProxyAPI` | CLIProxyAPI GitHub repo |
| `MGR_IMAGE` | `seakee/cpa-manager:latest` | CPA Manager image |
| `MGR_REPO` | `seakee/CPA-Manager` | CPA Manager GitHub repo |

## Troubleshooting

Version check fails:

```sh
docker logs --tail 50 cli-proxy-api
docker inspect cpa-manager
```

Docker Compose fails:

```sh
cd /root/cpa-deploy
docker compose config
docker compose ps
```

## License

MIT
