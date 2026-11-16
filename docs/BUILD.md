# 构建与发布

本文针对仓库维护者。工作流需在仓库 `main` 分支运行，使用 GitHub-hosted `ubuntu-24.04`。本地脚本依赖 Linux/GNU 工具链；可使用 Linux 或 WSL 调试。

## 构建选项

| 工作流 | 默认上游 | 驱动与加速 |
| --- | --- | --- |
| [Open](../.github/workflows/c8-660-open.yml) | ImmortalWrt `master`，可覆盖分支或提交 | mt76、原生 PPE、可选 WED / 流卸载 |
| [Closed](../.github/workflows/c8-660-closed.yml) | `chasey-dev/immortalwrt-mt798x-rebase` 的固定 `daa7695e855d98abbd1b2df42b1dc03812b267b3` | mt_wifi 7.6.7.3、HNAT、WARP/WED |

两个工作流均由 `workflow_dispatch` 手动启动。选择仓库 `main` 分支后设置输入参数：

| 参数 | 说明 |
| --- | --- |
| `publish_release` | `true`：发布独立变体的测试预发布；`false`：仅上传 7 天保留期的 Actions Artifact |
| `enable_cache` | 是否启用编译缓存；缓存命中与节省时间取决于上游版本和已有缓存 |
| `keep_releases` | 保留最近的同变体自动发布版本数，默认 3 |
| `wrt_branch` / `wrt_ref` | Open 可指定分支或提交；Closed 可覆盖默认源码提交 |
| `enable_wed` / `enable_flow_offloading` | Open 的 WED 与流卸载开关 |

发布标签分别使用 `c8-660-open-*`、`c8-660-closed-*`。发布仅允许从 `main` 执行；其他分支运行时保留为 Artifact，不创建 Release。发布成功后才执行同变体的历史 Release 清理，不交叉删除另一变体。

## Secrets

| 名称 | 用途 |
| --- | --- |
| `WRT_PW` | root 登录密码，必填；为空时构建失败 |
| `WRT_WORD` | Wi-Fi 密码，可选；为空时默认开放无线网络 |
| `INIT_BUILD_EXPECTED_SHA256` | 可选，覆盖固定的构建环境脚本 SHA-256 |

不要把密码写入 README、工作流文件或 Release 描述。镜像内包含设置后的认证信息；公开分发前应使用独立、已规划的首次启动凭据策略。

## 源码与锁定

- Open 默认跟随 `master`，不保证不同构建日期得到相同内核和软件包版本；发布时应核对构建日志与 manifest。
- Closed 固定固件源码提交；MTK LuCI 配套包提交见工作流 `WRT_MTK_APPS_REF` 与发布元数据。
- HomeProxy / sing-box 的打包规则由 `.github/proxy-locks.env` 及 `Scripts/ApplyProxyLocks.sh` 校验。2026-11-13 测试基线为 HomeProxy `20261111-r1`、sing-box `v1.15.0-alpha.13`（预发布版本）。
- 构建环境脚本按 `.github/init_build_environment.ref` 和 `.github/init_build_environment.sha256` 锁定。
- 两个定时更新工作流仅在独立分支提交更新并尝试创建 PR，不应自动合入 `main`。

## 配置入口

| 路径 | 作用 |
| --- | --- |
| `Config/GENERAL.txt`、`Config/GENERAL-CLOSED.txt` | 基础软件包配置 |
| `Config/NRADIO-C8-660*.txt`、`Config/OPEN.txt`、`Config/CLOSED.txt` | 设备与变体配置 |
| `Scripts/Packages.sh` | 第三方软件包管理 |
| `Scripts/Settings.sh` | 默认配置、密码和网络参数 |
| `Scripts/InstallC8ClosedTarget.sh`、`Scripts/InstallC8Overlay.sh` | 设备支持与覆盖文件 |
| `Scripts/TestRecentBuildRegressions.sh`、`Scripts/ValidateC8ClosedBuild.sh` | 构建前后校验 |

私有扩展可使用未追踪的 `Config/PRIVATE.txt` 与 `Scripts/PRIVATE.sh`。保留配置升级涉及 HomeProxy 配置格式变更时，应备份旧配置并检查代理服务状态，不能仅依据构建成功推断升级兼容。
