# CPA Stack 智能更新脚本

[![English](https://img.shields.io/badge/Language-English-blue)](./README.md)
[![简体中文](https://img.shields.io/badge/语言-简体中文-green)](./README.zh-CN.md)

这是一个兼容 BusyBox `sh` 的小脚本，用来智能更新 Docker Compose 里的：

- [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)
- [CPA Manager](https://github.com/seakee/CPA-Manager)

它会比较当前正在运行的本地版本和 GitHub 最新 Release。只有当上游版本更高时，才更新对应服务。

## 脚本作用

脚本会对每个服务执行下面的逻辑：

1. 读取当前正在运行的本地版本。
2. 访问 GitHub Release API 获取上游最新版本。
3. 如果本地版本等于或高于上游版本，就跳过。
4. 如果上游版本更高，就拉取配置的 Docker 镜像，并只重建对应服务。

默认项目和镜像如下：

| 服务 | GitHub Release 来源 | Docker 镜像 |
| --- | --- | --- |
| `cli-proxy-api` | `router-for-me/CLIProxyAPI` | `eceasy/cli-proxy-api:latest` |
| `cpa-manager` | `seakee/CPA-Manager` | `seakee/cpa-manager:latest` |

## 前置条件

- Linux/OpenWrt 类环境，可以使用 BusyBox `sh`。
- 已安装 Docker，并且可以使用 `docker compose`。
- 有 `curl`、`sed`、`grep`、`awk`、`sort`、`date`。
- 默认 Compose 部署目录是 `/root/cpa-deploy`。
- 容器名需要是 `cli-proxy-api` 和 `cpa-manager`。

脚本默认匹配类似下面的 Compose 服务结构：

```yaml
services:
  cli-proxy-api:
    image: eceasy/cli-proxy-api:latest
    container_name: cli-proxy-api

  cpa-manager:
    image: seakee/cpa-manager:latest
    container_name: cpa-manager
```

## 安装与更新

**交互模式** — 选择本地/远程、语言和部署目录：

```sh
curl -fsSL https://raw.githubusercontent.com/Souitou-iop/cpa-stack-smart-update/main/install.sh | sh
```

**远程安装** — 直接指定 `user@host`：

```sh
curl -fsSL https://raw.githubusercontent.com/Souitou-iop/cpa-stack-smart-update/main/install.sh | sh -s -- root@192.168.1.1
```

**本地安装** — 在服务器/旁路由上直接运行：

```sh
curl -fsSL https://raw.githubusercontent.com/Souitou-iop/cpa-stack-smart-update/main/install.sh | sh -s -- --local
```

指定自定义部署目录：

```sh
curl -fsSL https://raw.githubusercontent.com/Souitou-iop/cpa-stack-smart-update/main/install.sh | sh -s -- root@192.168.1.1 /opt/cpa-deploy
curl -fsSL https://raw.githubusercontent.com/Souitou-iop/cpa-stack-smart-update/main/install.sh | sh -s -- --local /opt/cpa-deploy
```

交互流程：

1. **选择语言** — English 或简体中文。
2. **选择模式** — 本地安装或远程 SSH 安装（通过参数指定时自动跳过）。
3. **检测安装状态** — 检查是否已存在脚本。
4. **未安装时** — 询问是否安装，安装完成后自动运行 `--check-only` 验证服务状态。
5. **已安装时** — 询问是否检查更新，将脚本与 GitHub 最新版本对比，发现新版本后询问是否更新，更新完成后自动验证服务状态。

## 更新后验证

一条命令检查全部——Compose 状态、CLIProxyAPI 端点、CPA Manager 端点：

```sh
sh /root/cpa-deploy/update-cpa-stack.sh --verify
```

## 自定义配置

可以通过环境变量覆盖默认部署目录、镜像和上游仓库：

```sh
STACK_DIR=/opt/cpa-deploy \
CLI_IMAGE=your-registry/cli-proxy-api:latest \
CLI_REPO=router-for-me/CLIProxyAPI \
MGR_IMAGE=your-registry/cpa-manager:latest \
MGR_REPO=seakee/CPA-Manager \
sh ./update-cpa-stack.sh --check-only
```

变量说明：

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `STACK_DIR` | `/root/cpa-deploy` | `docker-compose.yml` 所在目录。 |
| `CLI_IMAGE` | `eceasy/cli-proxy-api:latest` | `cli-proxy-api` 服务使用的镜像。 |
| `CLI_REPO` | `router-for-me/CLIProxyAPI` | 用于读取 CLIProxyAPI 最新 Release 的 GitHub 仓库。 |
| `MGR_IMAGE` | `seakee/cpa-manager:latest` | `cpa-manager` 服务使用的镜像。 |
| `MGR_REPO` | `seakee/CPA-Manager` | 用于读取 CPA Manager 最新 Release 的 GitHub 仓库。 |

## 版本识别方式

CLIProxyAPI 的本地版本来自容器最近日志中的版本行，例如：

```text
CLIProxyAPI Version: v7.1.44, Commit: fd30944, BuiltAt: 2026-06-03T17:06:42Z
```

CPA Manager 的本地版本来自当前运行镜像的 OCI label：

```sh
docker image inspect "$(docker inspect -f '{{.Image}}' cpa-manager)" \
  --format '{{index .Config.Labels "org.opencontainers.image.version"}}'
```

## 安全说明

- 第一次修改 Compose 前，脚本会备份为 `docker-compose.yml.bak-smart-update-YYYYmmddHHMMSS`。
- `.update-compose-backed-up` 标记文件用于避免反复生成备份。
- 脚本只更新 `cli-proxy-api` 和 `cpa-manager`。
- 脚本不会更新 Home Assistant 或其他服务。
- 脚本依赖 GitHub Release API；如果设备无法访问 GitHub，版本检查会失败。
- 版本比较依赖语义化版本标签，例如 `v7.1.44` 或 `1.5.5`。

## 故障排查

如果版本识别失败：

```sh
docker logs --tail 50 cli-proxy-api
docker inspect cpa-manager
curl -fsSL https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest
curl -fsSL https://api.github.com/repos/seakee/CPA-Manager/releases/latest
```

如果 Docker Compose 执行失败：

```sh
cd /root/cpa-deploy
docker compose config
docker compose ps
```

如果部署目录不同：

```sh
STACK_DIR=/your/stack/path sh /path/to/update-cpa-stack.sh --check-only
```

## 许可证

MIT
