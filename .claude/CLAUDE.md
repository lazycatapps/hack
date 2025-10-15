# CLAUDE.md

本文件为 Claude Code（claude.ai/code）在维护本仓库时提供操作指引。

## 仓库总览

这是 LazyCAT Apps 组织的 **hack** 仓库，集中存放可重用的工具链、Makefile、GitHub 工作流模板与初始化脚本，用于在组织内部快速搭建并统一项目结构。

面向使用者的完整说明请参阅仓库根目录的 `README.md`；本文件聚焦于维护流程、同步策略与风险提示。

## 核心架构

### 1. 基础 Makefile 系统（base.mk）

`base.mk` 是所有项目的核心依赖，项目只需在自身的 `Makefile` 中引入即可获得共用能力。

- **设计特点**
  - 所有默认目标都以 `-default` 结尾（如 `help-default`、`lpk-default`）
  - 项目可通过定义同名目标（不带 `-default`）实现覆盖
  - 文件末尾的通配规则 `%: %-default` 负责路由默认实现
  - 自动探测 LazyCAT Box 名称（`lzc-cli box default`），并在无法探测时给出告警
  - 提供 `print_info/print_success/print_warning/print_error` 等格式化输出
- **必填变量**
  - `PROJECT_NAME`：项目标识
  - `PROJECT_TYPE`：`lpk-only` 或 `docker-lpk`
- **可选变量**
  - `VERSION`：版本号，默认从 git 标签/提交推断
  - `REGISTRY`：Docker 仓库地址（默认基于 LazyCAT Box 推导，若 Box 未探测到则留空）
  - `APP_ID_PREFIX`、`APP_NAME`、`APP_ID` 等应用 ID 相关变量
- **容错与提示**
  - 当 `lzc-cli` 未安装或无法探测 Box 时使用 fallback，并通过 `make info` 和 `$(warning …)` 提示用户显式配置

### 2. 项目初始化脚本（scripts/lazycli.sh）

脚本支持三种工作模式：

1. **交互模式**：逐步引导用户选择项目类型与名称
2. **快速模式**：通过 `--type`、`--name` 参数一键生成
3. **同步模式**：使用 `--sync` 将仓库模板同步到现有项目

**主要功能**
- 可通过 curl 单行命令远程执行
- 使用环境变量 `HACK_REPO_BRANCH` 指定模板分支（默认 main）
- 下载 `base.mk`、`.editorconfig`、`.gitignore` 等共用文件
- 按项目类型拷贝工作流模板，并且始终同步 `workflows/common/cleanup-artifacts.yml`、`workflows/common/reusable-lpk-package.yml` 与 `workflows/docker-lpk/reusable-docker-image.yml`
  - `lpk-only`：下载触发层 `workflows/lpk-only/lpk-package.yml`，由项目侧调用共享的 `reusable-lpk-package.yml`
  - `docker-lpk`：初始化时复制触发层 `workflows/docker-lpk/docker-image.yml`，同步时仅更新 `workflows/common/reusable-docker-image.yml`、`workflows/docker-lpk/cleanup-docker-tags.yml`、`workflows/docker-lpk/lpk-package.yml`
- 生成包含真实可用目标说明的 `README.md`
- 可选初始化 Git 仓库并设置用户名、邮箱

### 3. 工作流模板

- **目录组织**
  - `workflows/common/`：通用工作流（`cleanup-artifacts.yml`）以及共享的复用层（`reusable-lpk-package.yml`）
  - `workflows/docker-lpk/`：Docker 相关触发与复用层（含 `reusable-docker-image.yml`）
  - `workflows/lpk-only/`：LPK 项目触发层（`lpk-package.yml`）
  - `workflows/docker-lpk/`：Docker + LPK 项目，包含：
    - `docker-image.yml`：默认触发层，初始化时复制到项目
    - `cleanup-docker-tags.yml`、`lpk-package.yml`：Docker + LPK 其他流程（其中 `lpk-package.yml` 负责准备上下文并调用共享的 LPK 复用层）
- **主要作用**
  - `cleanup-artifacts.yml`：定期清理历史构建产物
  - `lpk-package.yml` + `reusable-lpk-package.yml`：触发层负责事件判断与上下文准备，复用层调用 `lzc-cli` 完成构建与发布
  - `docker-image.yml` + `reusable-docker-image.yml`：组合实现镜像构建与推送，同时允许项目自定义触发条件
  - `cleanup-docker-tags.yml`：清理旧的 Docker 标签

## LazyCAT 平台集成检查

请定期核对 `README.md` 中列出的 CLI 用法仍然有效，并确认以下命令在实际环境可执行：

- `npm install -g @lazycatcloud/lzc-cli`
- `lzc-cli box default`、`lzc-cli project build`
- `lzc-cli app install <file.lpk>` / `lzc-cli app uninstall <app-id>`
- 生成的应用 ID 需符合 `APP_ID = APP_ID_PREFIX + APP_NAME`（示例：`cloud.lazycat.app.liu.myapp`）
- 当探测到 Box 名时，应能推导出 `docker-registry-ui.{BOX_NAME}.heiyu.space`

## 日常维护操作

### 脚本/模板测试

优先阅读 `README.md` 中的“快速开始”章节，内部已列出交互、快速、同步以及进程替换的命令示例。维护时至少验证：

1. 交互模式、快速模式各跑一次，确认生成内容与描述一致。
2. `./scripts/lazycli.sh --sync` 与 `./scripts/lazycli.sh --sync --sync-include-init` 行为符合预期。
3. 使用进程替换的远程执行方式时，附带 `--sync-target`、`--sync-workflow-type` 参数依然可用。

### 修改 base.mk 的注意事项

1. 所有默认目标必须保留 `-default` 后缀
2. 同时在 `lpk-only` 与 `docker-lpk` 项目中验证
3. 确认覆写机制仍然生效
4. 执行 `make help` 检查帮助输出

### 新增或调整工作流模板

1. 判断属于 common、lpk-only 还是 docker-lpk
2. 将文件放入对应子目录
3. 更新 `scripts/lazycli.sh` 中的 `copy_workflows` 下载列表
4. 更新 README 与本文件的相关描述，必要时确认 `--sync`、`--sync --sync-include-init` 以及带有 `--sync-target`/`--sync-workflow-type` 参数的非交互模式行为一致

### 文件修改规范

- `base.mk`：输出与注释保持英文
- `README.md` 可使用中文或英文，但需与仓库当前风格保持一致
- `.claude/CLAUDE.md` 使用中文维护
- 保持文件结尾无多余空格

## 项目类型说明

### lpk-only

适用于仅构建 LPK 包的项目（CLI、库等非容器化场景）。

- 需要实现的目标：`lpk`、`deploy`、`uninstall`

### docker-lpk

同时构建 Docker 镜像与 LPK 包的项目（服务、Web 应用等）。

- 额外目标：`docker-build`、`docker-push`、`docker-run`、`release`

## 仓库结构理念

- 尽量精简根目录，核心模板集中存放
- 脚本可直接通过 curl 下载执行，便于快捷初始化
- 以构建类型（lpk-only / docker-lpk）划分模板，而非语言
- 工作流保持无语言绑定逻辑，语言探测统一由 `base.mk` 处理

## 测试建议

- 交互/快速模式生成项目，确认文件列表与预期一致
- 对 Docker 项目执行 `--sync`，验证仅复用工作流被覆盖，触发层文件保持项目自定义
- 检查生成项目的 `README.md`、`Makefile` 是否包含正确的目标说明
- 在未安装 `lzc-cli` 的环境下执行 `make info`，确认 fallback 告警提示清晰

## 重要提醒

1. **不要直接修改下游项目的工作流**，统一在模板仓库更新并同步
2. **项目不得修改 base.mk**，如需调整请通过覆写目标实现
3. **务必保留 `-default` 后缀**，否则覆写机制会失效
4. **优先通过变量自定义行为**，避免直接改动公用模板
