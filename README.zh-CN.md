# CPA Stack 智能更新脚本

[![English](https://img.shields.io/badge/Language-English-blue)](./README.md)
[![简体中文](https://img.shields.io/badge/语言-简体中文-green)](./README.zh-CN.md)

自动检测并更新 Docker Compose 中的 CLIProxyAPI（单容器架构），只在有新版本时才更新，不影响其他服务。

## 快速开始

在你的电脑上执行一条命令：

```sh
curl -fsSL https://raw.githubusercontent.com/Souitou-iop/cpa-stack-smart-update/main/install.sh -o /tmp/install-cpa.sh && sh /tmp/install-cpa.sh
```

脚本会引导你完成：选择语言 → 远程或本地安装 → 自动检测 → 安装或更新 → 验证服务。

逻辑说明：
- 检测到 CLIProxyAPI 新版本时自动拉取镜像并重建容器，全程无需确认；`--yes` 仅为兼容旧定时任务保留

快捷方式：
- 远程安装：`sh /tmp/install-cpa.sh root@192.168.1.1`
- 本地安装：`sh /tmp/install-cpa.sh --local`
- 自定义目录：`sh /tmp/install-cpa.sh root@192.168.1.1 /opt/cpa-deploy`

## 这个脚本做什么？

简单来说：帮你自动更新旁路由/服务器上的 CLIProxyAPI Docker 服务。

```
检查版本 → 有新版本？→ 拉取镜像 → 重建容器 → 清理悬空镜像 → 验证服务
              ↓ 没有
            跳过
```

默认更新的服务：

| 服务 | 镜像 | 用途 |
| --- | --- | --- |
| CLIProxyAPI | `eceasy/cli-proxy-api:latest` | API 代理服务 |

## 一键验证

更新后，一条命令检查所有服务是否正常：

```sh
sh /mnt/docker-data/cli-proxy-api/update-cpa-stack.sh --verify
```

会自动检查：容器状态 + config.yaml v8 布局 + CLIProxyAPI 端点（`/`、`/management.html`）+ CPA Usage Keeper 独立面板（`:8318`）+ 业务 API（用 `access.api-keys` 中的密钥请求 `/v1/models`）。

## 只清理旧镜像

如果只想清理更新后遗留的悬空 Docker 镜像，不更新服务：

```sh
sh /mnt/docker-data/cli-proxy-api/update-cpa-stack.sh --cleanup-only
```

## SSH 认证方式

脚本支持两种 SSH 认证方式：

### 1. 免密 SSH（密钥认证）- 推荐

设置 SSH 密钥实现免密登录：

```sh
# 生成 SSH 密钥（如果还没有）
ssh-keygen -t ed25519

# 复制公钥到旁路由
ssh-copy-id root@192.168.1.1
```

### 2. 密码认证

如果没有设置 SSH 密钥，脚本会：
1. 提示输入 SSH 用户名（默认：root）
2. 提示输入 SSH 密码
3. 自动安装 `sshpass`（支持 macOS、Ubuntu、CentOS）

**注意**：密码认证需要 `sshpass` 工具，脚本会尝试自动安装。

## 前置条件

- 旁路由或服务器已安装 Docker
- 可以通过 SSH 连接（远程安装时）
- 能访问 GitHub（用于检查更新和下载脚本）

## 安全说明

- 更新前自动成对备份 `docker-compose.yml` 和 `config.yaml`（各保留最近 1 份）
- 只更新 CLIProxyAPI，不影响其他服务
- 版本比较基于 GitHub Release 标签
- 支持 `--rollback` 回滚到最近一次成对备份
- 更新成功后清理悬空镜像；仍被其他容器使用的镜像自动跳过

## 自动更新（定时任务）

脚本本身无需确认，定时任务可直接执行（`--yes` 仅为兼容保留）：

```sh
sh /mnt/docker-data/cli-proxy-api/update-cpa-stack.sh --yes
```

## 自定义配置

如果部署目录不是默认的 `/mnt/docker-data/cli-proxy-api`（脚本会自动回退检测 `/mnt/docker-data/cpa-deploy`），或需要使用自定义镜像：

```sh
STACK_DIR=/opt/cpa-deploy \
CLI_IMAGE=your-registry/cli-proxy-api:latest \
sh /mnt/docker-data/cli-proxy-api/update-cpa-stack.sh --check-only
```

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `STACK_DIR` | `/mnt/docker-data/cli-proxy-api` | 部署目录 |
| `CLI_IMAGE` | `eceasy/cli-proxy-api:latest` | CLIProxyAPI 镜像 |
| `CLI_REPO` | `router-for-me/CLIProxyAPI` | CLIProxyAPI GitHub 仓库 |

## 故障排查

版本检查失败：

```sh
docker logs --tail 50 cli-proxy-api
```

备份与回滚：

```sh
ls -l /mnt/docker-data/cli-proxy-api/*.bak-*
sh /mnt/docker-data/cli-proxy-api/update-cpa-stack.sh --rollback
```

Docker Compose 执行失败：

```sh
cd /mnt/docker-data/cli-proxy-api
docker compose config
docker compose ps
```

## 许可证

MIT
