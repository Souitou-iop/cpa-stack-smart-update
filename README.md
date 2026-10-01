# CPA Stack Smart Update

[![English](https://img.shields.io/badge/Language-English-blue)](./README.md)
[![简体中文](https://img.shields.io/badge/语言-简体中文-green)](./README.zh-CN.md)

Automatically detect and update CLIProxyAPI in your Docker Compose stack (single-container architecture). Only updates when a new version is available, leaves other services untouched.

## Quick Start

Run this command on your computer:

```sh
curl -fsSL https://raw.githubusercontent.com/Souitou-iop/cpa-stack-smart-update/main/install.sh -o /tmp/install-cpa.sh && sh /tmp/install-cpa.sh
```

The script will guide you through: language → remote or local install → detect → install or update → verify.

How it works:
- Automatically pulls the new image and recreates the container when a new CLIProxyAPI version is found — no confirmation needed; `--yes` is kept only for backward compatibility with existing cron jobs

Shortcuts:
- Remote install: `sh /tmp/install-cpa.sh root@192.168.1.1`
- Local install: `sh /tmp/install-cpa.sh --local`
- Custom directory: `sh /tmp/install-cpa.sh root@192.168.1.1 /opt/cpa-deploy`

## What Does This Do?

In simple terms: automatically updates the CLIProxyAPI Docker service on your router/server.

```
Check version → New version? → Pull image → Recreate container → Clean dangling images → Verify
                    ↓ No
                  Skip
```

Default service updated:

| Service | Image | Purpose |
| --- | --- | --- |
| CLIProxyAPI | `eceasy/cli-proxy-api:latest` | API proxy service |

## One-Command Verify

After updating, check everything with one command:

```sh
sh /mnt/docker-data/cli-proxy-api/update-cpa-stack.sh --verify
```

Automatically checks: container status + config.yaml v8 layout + CLIProxyAPI endpoints (`/`, `/management.html`) + CPA Usage Keeper panel (`:8318`) + business API (`/v1/models` authorized with a key from `access.api-keys`).

## Cleanup Only

To clean dangling Docker images left by previous updates without updating services:

```sh
sh /mnt/docker-data/cli-proxy-api/update-cpa-stack.sh --cleanup-only
```

## SSH Authentication

The script supports two SSH authentication methods:

### 1. Key-based (Passwordless) - Recommended

Set up SSH keys for passwordless access:

```sh
# Generate SSH key (if you don't have one)
ssh-keygen -t ed25519

# Copy key to router
ssh-copy-id root@192.168.1.1
```

### 2. Password Authentication

If you haven't set up SSH keys, the script will:
1. Prompt for SSH username (default: root)
2. Prompt for SSH password
3. Automatically install `sshpass` if needed (supports macOS, Ubuntu, CentOS)

**Note**: Password authentication requires `sshpass` to be installed. The script will attempt to install it automatically.

## Requirements

- Docker installed on your router/server
- SSH access (for remote install)
- GitHub access (for checking updates and downloading scripts)

## Safety

- Auto-backs up `docker-compose.yml` and `config.yaml` as a pair before any changes (1 pair retained)
- Only updates CLIProxyAPI, ignores other services
- Version comparison based on GitHub Release tags
- `--rollback` restores the most recent paired backup
- After a successful update, dangling images are cleaned; images still used by other containers are skipped automatically

## Automated Updates (Cron)

The script needs no confirmation, so cron jobs can run it directly (`--yes` is kept for compatibility):

```sh
sh /mnt/docker-data/cli-proxy-api/update-cpa-stack.sh --yes
```

## Configuration

If your stack directory is not the default `/mnt/docker-data/cli-proxy-api` (the script automatically falls back to `/mnt/docker-data/cpa-deploy`), or you need a custom image:

```sh
STACK_DIR=/opt/cpa-deploy \
CLI_IMAGE=your-registry/cli-proxy-api:latest \
sh /mnt/docker-data/cli-proxy-api/update-cpa-stack.sh --check-only
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `STACK_DIR` | `/mnt/docker-data/cli-proxy-api` | Stack directory |
| `CLI_IMAGE` | `eceasy/cli-proxy-api:latest` | CLIProxyAPI image |
| `CLI_REPO` | `router-for-me/CLIProxyAPI` | CLIProxyAPI GitHub repo |

## Troubleshooting

Version check fails:

```sh
docker logs --tail 50 cli-proxy-api
```

Backups and rollback:

```sh
ls -l /mnt/docker-data/cli-proxy-api/*.bak-*
sh /mnt/docker-data/cli-proxy-api/update-cpa-stack.sh --rollback
```

Docker Compose fails:

```sh
cd /mnt/docker-data/cli-proxy-api
docker compose config
docker compose ps
```

## License

MIT
