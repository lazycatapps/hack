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

Hack 是 LazyCAT Apps 组织的统一模板仓库，用于快速初始化项目、共享可复用的 Makefile 规则以及 GitHub Actions 工作流。通过引入本仓库提供的脚本与模板，可以在不同项目之间保持一致的工程结构与自动化能力。

## 核心能力

- **base.mk**：提供带有 `%-default` 覆写机制的通用 Makefile，自动探测 LazyCAT Box、版本号与镜像地址，并在无法探测 Box 时给出告警提示。
- **初始化脚本 (`scripts/lazycli.sh`)**：
  - 交互模式：逐步选择项目类型与名称。
  - 快速模式：`--type` + `--name` 一次性生成。
  - 同步模式：`--sync` 更新现有项目模板。
  - 初始化时会生成 `README.md`、`Makefile`、`.editorconfig`、`.gitignore`，并根据项目类型复制对应工作流；同步时仅更新可安全覆盖的文件（如复用工作流）。
- **工作流模板**：
  - `workflows/common/cleanup-artifacts.yml`：各类型项目共用的 Actions 产物清理任务。
  - `workflows/common/reusable-lpk-package.yml`：统一的 LPK 打包复用层，供不同触发流程调用。
  - `workflows/docker-lpk/reusable-docker-image.yml`：Docker 镜像构建的复用逻辑。
  - `workflows/lpk-only/lpk-package.yml`：纯 LPK 项目的触发工作流。
  - `workflows/docker-lpk/`：
    - `docker-image.yml`：初始化时生成的默认触发配置，项目可后续自行调整。
    - `cleanup-docker-tags.yml`、`lpk-package.yml`：Docker + LPK 专属触发流程，负责组织共享复用层。

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

Short flags such as `-t`, `-n`, `-s`, `-I`, `-T`, and `-W` are also supported for non-interactive usage.

### 4. 自定义 Git 用户的远程执行

```bash
# Remote execution with custom git user
GIT_USER_NAME="John Doe" GIT_USER_EMAIL="john@example.com" \
  bash <(curl -fsSL https://raw.githubusercontent.com/lazycatapps/hack/main/scripts/lazycli.sh)
```

如果你需要自定义应用 ID 前缀，可以在运行脚本前导出 `APP_ID_PREFIX` 环境变量；初始化步骤会将生成的 `Makefile` 更新为使用该值。

通过在命令前注入 `GIT_USER_NAME`、`GIT_USER_EMAIL` 环境变量，可以在远程执行脚本时写入指定的 Git 用户信息，方便在新仓库中直接使用。

## 使用 base.mk

在项目的 `Makefile` 中：

```makefile
PROJECT_NAME := my-app
PROJECT_TYPE := lpk-only  # 或 docker-lpk

include base.mk
```

常用目标：

- `make help`：查看所有可用目标。
- `make info`：打印项目类型、版本与 App ID。
- `make clean`：清理构建产物。
- `make lpk` / `make deploy` / `make uninstall`：管理 LPK 包。
- Docker 项目额外支持 `make docker-build`、`make docker-push`、`make docker-run`、`make release`。

若 `lzc-cli` 未安装或默认 Box 无法探测，`make info` 将提示用户手动配置 `LAZYCAT_BOX_NAME` 或 `REGISTRY`。

## 工作流拆分策略

为了兼顾共享逻辑与项目自定义需求，Docker 镜像构建流程拆分为：

1. **触发工作流**（`.github/workflows/docker-image.yml`）：由模板提供默认配置，初始化时生成，后续由项目根据需要自行修改（自定义 `on` 条件、变量、通知等）。
2. **复用工作流**（`.github/workflows/reusable-docker-image.yml`）：仅包含构建与推送逻辑，模板更新时通过 `--sync` 自动下发，项目无需手动维护。

这样可以在保证构建流程一致性的同时，让每个项目自由定义触发策略。

同理，LPK 打包逻辑迁移至 `workflows/common/reusable-lpk-package.yml`，而触发层（`workflows/lpk-only/lpk-package.yml` 与 `workflows/docker-lpk/lpk-package.yml`）仅负责事件入口与上下文准备。项目侧可以自由修改触发条件，共享的打包步骤由初始化/同步脚本保持一致。

## LazyCAT 平台集成

- 安装 CLI：`npm install -g @lazycatcloud/lzc-cli`
- 常用命令：
  - `lzc-cli box default`：查看默认 LazyCAT Box。
  - `lzc-cli project build`：构建 LPK 包。
  - `lzc-cli app install <file.lpk>` / `lzc-cli app uninstall <app-id>`：安装或卸载应用。
- 应用 ID 约定：`APP_ID = APP_ID_PREFIX + APP_NAME`（默认前缀 `cloud.lazycat.app.`）。
- Docker Registry 会在配置成功的情况下根据 Box 自动推导为 `docker-registry-ui.{BOX_NAME}.heiyu.space`。

## 测试与验证建议

1. 在本地分别使用交互模式 / 快速模式生成项目，确认文件列表及初始化内容正确。
2. 对生成的 Docker 项目执行 `--sync`，验证仅复用工作流被更新，触发文件保持项目自定义。
3. 在未安装 `lzc-cli` 环境下运行 `make info`，确认 fallback 告警可读。

## 贡献指南

- 变更脚本或工作流时，务必同步维护 `scripts/lazycli.sh` 的下载列表与相关文档说明。
- 提交前检查文件行尾、运行一次初始化脚本或 `--sync` 模式，确认模板可在真实项目中顺利使用。
