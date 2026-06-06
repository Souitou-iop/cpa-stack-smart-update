# CPA Stack 智能更新脚本

[![English](https://img.shields.io/badge/Language-English-blue)](./README.md)
[![简体中文](https://img.shields.io/badge/语言-简体中文-green)](./README.zh-CN.md)

自动检测并更新 Docker Compose 中的 CLIProxyAPI 和 CPA Manager，只在有新版本时才更新，不影响其他服务。

## 快速开始

在你的电脑上执行一条命令：

```sh
curl -fsSL https://raw.githubusercontent.com/Souitou-iop/cpa-stack-smart-update/main/install.sh -o /tmp/install-cpa.sh && sh /tmp/install-cpa.sh
```

脚本会引导你完成：选择语言 → 远程或本地安装 → 自动检测 → 安装或更新 → 验证服务。

逻辑说明：
- **脚本更新**（update-cpa-stack.sh）：检测到新版本时自动更新，无需确认
- **服务更新**（CLIProxyAPI / CPA Manager）：检测到新版本时会询问用户是否确认更新

快捷方式：
- 远程安装：`sh /tmp/install-cpa.sh root@192.168.1.1`
- 本地安装：`sh /tmp/install-cpa.sh --local`
- 自定义目录：`sh /tmp/install-cpa.sh root@192.168.1.1 /opt/cpa-deploy`

## 这个脚本做什么？

简单来说：帮你自动更新旁路由/服务器上的两个 Docker 服务。

```
检查版本 → 有新版本？→ 拉取镜像 → 重建容器 → 验证服务
              ↓ 没有
            跳过
```

默认更新的两个服务：

| 服务 | 镜像 | 用途 |
| --- | --- | --- |
| CLIProxyAPI | `eceasy/cli-proxy-api:latest` | API 代理服务 |
| CPA Manager | `seakee/cpa-manager:latest` | 管理面板 |

## 一键验证

更新后，一条命令检查所有服务是否正常：

```sh
sh /root/cpa-deploy/update-cpa-stack.sh --verify
```

会自动检查：容器状态 + CLIProxyAPI 端点 + CPA Manager 端点。

## 前置条件

- 旁路由或服务器已安装 Docker
- 可以通过 SSH 连接（远程安装时）
- 能访问 GitHub（用于检查更新和下载脚本）

## 安全说明

- 更新前自动备份 `docker-compose.yml`
- 只更新 CLIProxyAPI 和 CPA Manager，不影响其他服务
- 检测到新版本时会询问用户是否确认更新
- 版本比较基于 GitHub Release 标签

## 自动更新（定时任务）

如果需要定时自动更新（如 cron），使用 `--yes` 参数跳过确认：

```sh
sh /root/cpa-deploy/update-cpa-stack.sh --yes
```

## 自定义配置

如果部署目录不是默认的 `/root/cpa-deploy`，或需要使用自定义镜像：

```sh
STACK_DIR=/opt/cpa-deploy \
CLI_IMAGE=your-registry/cli-proxy-api:latest \
MGR_IMAGE=your-registry/cpa-manager:latest \
sh /root/cpa-deploy/update-cpa-stack.sh --check-only
```

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `STACK_DIR` | `/root/cpa-deploy` | 部署目录 |
| `CLI_IMAGE` | `eceasy/cli-proxy-api:latest` | CLIProxyAPI 镜像 |
| `CLI_REPO` | `router-for-me/CLIProxyAPI` | CLIProxyAPI GitHub 仓库 |
| `MGR_IMAGE` | `seakee/cpa-manager:latest` | CPA Manager 镜像 |
| `MGR_REPO` | `seakee/CPA-Manager` | CPA Manager GitHub 仓库 |

## 故障排查

版本检查失败：

```sh
docker logs --tail 50 cli-proxy-api
docker inspect cpa-manager
```

Docker Compose 执行失败：

```sh
cd /root/cpa-deploy
docker compose config
docker compose ps
```

## 许可证

MIT
