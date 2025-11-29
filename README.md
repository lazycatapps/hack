# Hack

## TL;DR

```bash
# 1. 创建 LPK 项目
bash <(curl -fsSL https://raw.githubusercontent.com/lazycatapps/hack/main/scripts/lazycli.sh) --type lpk-only --name my-library

# 2. 创建 Docker + LPK 项目
bash <(curl -fsSL https://raw.githubusercontent.com/lazycatapps/hack/main/scripts/lazycli.sh) --type docker-lpk --name my-service

# 3. 同步配置到现有项目
bash <(curl -fsSL https://raw.githubusercontent.com/lazycatapps/hack/main/scripts/lazycli.sh) --sync
```

## 概述

Hack 是 Lazycat Apps 组织的统一模板仓库，用于快速初始化项目、共享可复用的 Makefile 规则以及 GitHub Actions 工作流。通过引入本仓库提供的脚本与模板，可以在不同项目之间保持一致的工程结构与自动化能力。

## 你能用它做什么

- 一分钟内创建符合 Lazycat 规范的 LPK 或 Docker+LPK 项目，带基础工程与工作流。
- 让已有项目与模板保持同步，安全更新 Makefile、复用工作流等通用资产。
- 直接复用内置的 Make 目标与 CI 工作流，减少自定义脚本维护成本。
- 在大规模项目集群中统一使用同一套工作流程与规则，显著降低单个项目的日常维护成本。
- 基于模板自带的 GitHub Actions 工作流自动构建正式 LPK，持续产出可上架的制品。

## 前置条件

- 操作系统：macOS 或 Linux，已安装 bash、curl、make。
- 工具链：Docker（仅 Docker+LPK 项目需要），npm（用于安装 `@lazycatcloud/lzc-cli`），git。
- 账号配置：已登录 Lazycat Box 对应的 Registry（Docker 项目），可选设置 `APP_ID_PREFIX`、`GIT_USER_NAME`、`GIT_USER_EMAIL`。
- 依赖检查：可通过 `make check-tools` 或 README 中的安装命令补齐。

## 快速开始

### 1. 交互初始化（推荐）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/lazycatapps/hack/main/scripts/lazycli.sh)
```

脚本会引导你选择项目类型、填写项目名称，并生成基础目录结构。

### 2. 快速模式

```bash
# 创建 LPK 项目
bash <(curl -fsSL https://raw.githubusercontent.com/lazycatapps/hack/main/scripts/lazycli.sh) --type lpk-only --name my-library

# 创建 Docker + LPK 项目
bash <(curl -fsSL https://raw.githubusercontent.com/lazycatapps/hack/main/scripts/lazycli.sh) --type docker-lpk --name my-service
```

### 3. 同步模板到现有项目

```bash
cd your-existing-project
bash <(curl -fsSL https://raw.githubusercontent.com/lazycatapps/hack/main/scripts/lazycli.sh) --sync

# 也可以通过下列 make 命令触发同步
make config-sync
```

同步时会自动更新通用文件以及复用型工作流（例如 `reusable-docker-image.yml`），不会覆盖项目已经定制的触发层工作流。

若希望在同步阶段一并覆盖初始化时才生成的触发文件（如 `docker-image.yml`），可以额外传入 `--sync-include-init`：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/lazycatapps/hack/main/scripts/lazycli.sh) --sync --sync-include-init
```

通过进程替换的方式执行脚本可以保留交互体验；若你在 CI 等非交互场景需要运行同步，也可以显式传入 `--sync-target`（`all`、`makefile`、`workflows`、`configs`）以及 `--sync-workflow-type`（用于 `workflows` 场景）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/lazycatapps/hack/main/scripts/lazycli.sh) \
  --sync --sync-target workflows --sync-workflow-type docker-lpk

```

非交互场景也可以使用短参数：`-t` 对应 `--type`，`-n` 对应 `--name`，`-s` 对应 `--sync`，`-I` 对应 `--sync-include-init`，`-T` 对应 `--sync-target`，`-W` 对应 `--sync-workflow-type`，便于脚本化调用时快速输入。

CI 最小同步示例（仅同步 Docker 工作流）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/lazycatapps/hack/main/scripts/lazycli.sh) --sync --sync-target workflows --sync-workflow-type docker-lpk
```

### 4. 自定义 Git 用户的远程执行

```bash
# 使用自定义 Git 用户进行远程执行
GIT_USER_NAME="John Doe" GIT_USER_EMAIL="john@example.com" \
  bash <(curl -fsSL https://raw.githubusercontent.com/lazycatapps/hack/main/scripts/lazycli.sh)
```

在命令前设置 `GIT_USER_NAME`、`GIT_USER_EMAIL`，脚本会同步写入新仓库的 Git 配置，远程执行也能保留你的身份信息。

## 使用 base.mk

在项目的 `Makefile` 中：

```makefile
PROJECT_NAME := my-app
PROJECT_TYPE := lpk-only  # 或 docker-lpk

include base.mk
```

初始化脚本会自动写入上述片段，日常不需要手动调整；仅在项目名或类型需要变更时再更新对应变量即可。

### 目标清单与作用

- 常用起步：
  - `info`：查看项目类型、版本与 App ID。
  - `lpk` / `deploy`：打包或打包并安装 LPK。
  - Docker 项目：`docker-build` 构建镜像，`docker-run` / `run` 本地运行。
  - `config-sync`：通过 LazyCLI 同步模板。
- 通用：
  - `help`：查看帮助。
  - `info`：查看项目信息。
  - `clean`：清理产物。
  - `config-sync`：通过 LazyCLI 同步模板。
  - `base-mk-version`：查看 base.mk 版本标识。
  - `base-mk-update-version`：更新 base.mk 版本标识。
- LPK：
  - `lpk`：打包。
  - `deploy`：打包并安装。
  - `uninstall`：卸载（保留数据）。
  - `uninstall-clean`：卸载并清理数据。
  - `list-packages`：列出本地 LPK。
- Docker（仅 docker-lpk）：
  - `docker-build`：构建镜像。
  - `docker-push`：推送镜像。
  - `docker-run` / `run`：本地运行容器。
  - `stop`：停止并移除容器。
  - `restart`：重启容器。
  - `logs`：查看容器日志。
  - `shell`：进入容器。
- Go 工具链：
  - `fmt`：格式化。
  - `vet`：静态检查。
  - `test`：运行测试。
  - `test-coverage`：生成覆盖率报告。
  - `tidy`：维护依赖。
  - `lint`：格式化并执行 vet。
  - `check`：执行 lint 与测试。
- 发布与工具：
  - `release`：构建发布包。
  - `install-lzc-cli`：安装 lzc-cli。
  - `install-docker2lzc`：安装 docker2lzc。
  - `appstore-login`：登录应用市场。
  - `version`：显示版本信息。
  - `check-tools`：检查依赖（bash、curl、make、lzc-cli；`docker-lpk` 项目额外检查 `docker2lzc` 和 `docker`）。

若 `lzc-cli` 未安装或默认 Box 无法探测，`make info` 将提示用户手动配置 `LAZYCAT_BOX_NAME` 或 `REGISTRY`。

## 初始化后做什么

1. 生成清单：Docker 项目可用 `docker2lzc` 基于 Dockerfile/镜像生成 `lzc-manifest.yml`，补充权限与元数据。
2. 本地调试：
   - LPK 项目：`make deploy` 安装并调试本地包。
   - Docker 项目：`make docker-run`（或 `make run`）启动容器，配合 `make logs` / `make shell` 观察。
3. 打包与发布：`make lpk` 生成 LPK，`make deploy` 本地安装验证；推送代码到 GitHub 后，模板工作流会构建正式 LPK 产物，供分发或上架。

## GitHub Actions 配置

- LPK 项目：在仓库 Secrets 中设置 `LAZYCAT_USERNAME`、`LAZYCAT_PASSWORD`，用于发布或上传 LPK。
- Docker+LPK 项目：除上述外，还需 `DOCKERHUB_USERNAME`、`DOCKERHUB_TOKEN` 以推送/复制镜像（若在组织级别已配置则无需逐仓库重复设置）；可选仓库变量 `DOCKER_CONTEXT`、`DOCKERFILE_PATH`、`DOCKER_TARGET`、`ENABLE_GO_TESTS`、`GO_VERSION`、`GO_TEST_DIR` 配置构建参数。
- 完成配置后，推送代码即可由模板工作流自动构建并产出 LPK（发布版本会自动上架，非发布版本会作为构建产物上传）。

## 工作流拆分策略

为了兼顾共享逻辑与项目自定义需求，Docker 镜像构建流程拆分为：

1. **触发工作流**（`.github/workflows/docker-image.yml`）：由模板提供默认配置，初始化时生成，后续由项目根据需要自行修改（自定义 `on` 条件、变量、通知等）。
2. **复用工作流**（`.github/workflows/reusable-docker-image.yml`）：仅包含构建与推送逻辑，模板更新时通过 `--sync` 自动下发，项目无需手动维护。

这样可以在保证构建流程一致性的同时，让每个项目自由定义触发策略。

同理，LPK 打包逻辑迁移至 `workflows/common/reusable-lpk-package.yml`，而触发层（`workflows/lpk-only/lpk-package.yml` 与 `workflows/docker-lpk/lpk-package.yml`）仅负责事件入口与上下文准备。项目侧可以自由修改触发条件，共享的打包步骤由初始化/同步脚本保持一致。

## Lazycat 平台集成

- 安装 CLI：`npm install -g @lazycatcloud/lzc-cli`
- 常用命令：
  - `lzc-cli box default`：查看默认 Lazycat Box。
  - `lzc-cli project build`：构建 LPK 包。
  - `lzc-cli app install <file.lpk>` / `lzc-cli app uninstall <app-id>`：安装或卸载应用。
- 应用 ID 约定：`APP_ID = APP_ID_PREFIX + APP_NAME`（默认前缀 `cloud.lazycat.app.`）。
- 如需自定义应用 ID 前缀，可在运行脚本前设置 `APP_ID_PREFIX`，初始化会在生成的 `Makefile` 中写入该前缀。
- Docker Registry 会在配置成功的情况下根据 Box 自动推导为 `docker-registry-ui.{BOX_NAME}.heiyu.space`。

## 将已有项目迁移到模板

1. 备份当前仓库，避免同步覆盖你的自定义工作流或配置。
2. 在项目根目录执行：
   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/lazycatapps/hack/main/scripts/lazycli.sh) --sync --sync-include-init
   ```
   这会同步 `base.mk`、工作流和基础配置，并覆盖初始化阶段才生成的触发文件。
3. 还原必要的自定义：对比并恢复你需要保留的改动（如 `lzc-build.yml` 等项目特有文件）。
4. 验证：运行 `make help` 查看目标，使用 `make lpk` / `make deploy`（Docker 项目用 `make docker-run`/`make run`）验证打包与调试流程。

## 初始化后你会看到什么

- `README.md`、`Makefile`、`.editorconfig`、`.gitignore` 等基础工程文件。
- `.github/workflows/` 下的触发层工作流（按项目类型生成）以及复用工作流。
- 对应项目类型的示例目标已注入 `Makefile`，直接 `make help` 可查看。

## 测试与验证建议

1. 在本地分别使用交互模式 / 快速模式生成项目，确认文件列表及初始化内容正确。
2. 对生成的 Docker 项目执行 `--sync`，验证仅复用工作流被更新，触发文件保持项目自定义。
3. 在未安装 `lzc-cli` 环境下运行 `make info`，确认 fallback 告警可读。

## 常见问题 / 排障

- `lzc-cli` 未安装：按“Lazycat 平台集成”中的命令安装或执行 `make install-lzc-cli`。
- 无法探测 Lazycat Box / Registry：手动导出 `LAZYCAT_BOX_NAME` 或 `REGISTRY`，再运行 `make info` 确认。
- Docker 登录失败：确保已登录目标 Registry（`docker login docker-registry-ui.{BOX_NAME}.heiyu.space`）。
- 交互失败（CI 环境）：改用文档中的非交互短参示例运行。
- Make 目标缺失：运行 `make help` 确认 `base.mk` 已被正确包含；运行 `make check-tools` 可查看已检测到的依赖（bash、curl、make、lzc-cli，Docker 项目还包括 `docker2lzc`/`docker`）。

## 贡献指南

- 变更脚本或工作流时，务必同步维护 `scripts/lazycli.sh` 的下载列表与相关文档说明。
- 提交前检查文件行尾、运行一次初始化脚本或 `--sync` 模式，确认模板可在真实项目中顺利使用。
