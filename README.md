# ImmortalWrt · NRadio C8-660

[![Open build](https://github.com/osGex0o0II/ImmortalWrt-NRadio-C8-660/actions/workflows/c8-660-open.yml/badge.svg)](https://github.com/osGex0o0II/ImmortalWrt-NRadio-C8-660/actions/workflows/c8-660-open.yml) [![Closed build](https://github.com/osGex0o0II/ImmortalWrt-NRadio-C8-660/actions/workflows/c8-660-closed.yml/badge.svg)](https://github.com/osGex0o0II/ImmortalWrt-NRadio-C8-660/actions/workflows/c8-660-closed.yml)

为 NRadio C8-660（WT9103 / MT7981B）提供 Open 与 Closed 两套 ImmortalWrt 固件构建配置。两种固件采用独立工作流、驱动栈及发布标签。

**状态：测试阶段。** 2026 年 11 月 13 日的两次构建已通过编译、设备树与根文件系统检查，尚未完成实机启动、升级、Wi-Fi、5G 和硬件加速验证。CI 成功不等于设备兼容性验证通过。

## 固件变体

| 项目 | Open | Closed |
| --- | --- | --- |
| 上游源码 | [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) `master` | [chasey-dev](https://github.com/chasey-dev/immortalwrt-mt798x-rebase) `25.12`（固定提交） |
| Wi-Fi 驱动 | mt76 | MediaTek `mt_wifi 7.6.7.3` |
| 加速方案 | 原生 PPE + mt76 WED | HNAT + WARP/WED |
| 2026-11-13 测试内核 | Linux 6.18.60 | Linux 6.12.112 |
| 工作流 | [Open (mt76)](.github/workflows/c8-660-open.yml) | [Closed (mt_wifi)](.github/workflows/c8-660-closed.yml) |
| 发布标签 | `c8-660-open-*` | `c8-660-closed-*` |

Open 默认跟随上游 `master`，后续构建版本可能变化；可通过工作流输入指定分支或提交。Closed 默认固定上游提交 `daa7695e855d98abbd1b2df42b1dc03812b267b3`。

## 下载与构建

- [Releases](https://github.com/osGex0o0II/ImmortalWrt-NRadio-C8-660/releases) — 固件发布与校验文件
- [2026-11-13 双变体测试预发布](https://github.com/osGex0o0II/ImmortalWrt-NRadio-C8-660/releases/tag/c8-660-2026.11.13-test1) — 历史合并测试包；后续按 Open / Closed 分别发布
- [Actions](https://github.com/osGex0o0II/ImmortalWrt-NRadio-C8-660/actions) — 在 `main` 上手动运行对应构建工作流

首次使用需设置仓库 Actions Secret `WRT_PW`（root 密码，必填）；`WRT_WORD` 为 Wi-Fi 密码，未设置时无线网络为**开放网络**。构建与发布选项见 [构建说明](docs/BUILD.md)。

**现有测试预发布使用非公开 root 测试密码，仅适用于持有该密码的测试者。** 其他用户应自行构建，不应将该测试包用作通用安装镜像。

## 硬件与默认设置

| 项目 | 配置 |
| --- | --- |
| 处理器 | MediaTek MT7981B |
| 内存 / 闪存 | 512 MB DDR4 / 512 MB SPI-NAND |
| 无线 | MT7976CN，双频 Wi-Fi 6 |
| 5G 模组 | Quectel RM520N-CN |
| 有线端口 | 1 × 2.5 GbE、3 × 1 GbE |
| 管理地址 | `192.168.1.1` |
| 管理界面 | LuCI / Aurora / 简体中文 |

预装 C8 蜂窝及短信管理组件。Open 默认包含 HomeProxy / sing-box；Closed 不默认包含代理组件。其他包以实际固件的 manifest 为准。

## 刷机与升级

| 产物 | 用途 |
| --- | --- |
| `*-factory.bin` | 首次安装；必须按设备实际引导及分区布局确定刷写方式 |
| `*-sysupgrade.bin` | 经验证的同变体兼容升级；不可跨 Open / Closed 混刷 |
| `*-initramfs.bin` | 内存启动与调试，不直接写入闪存 |
| `*.manifest` | 固件包清单 |
| `sha256sums` | 按发布附件的实际文件名校验 SHA-256 |

原厂 NROS **不能直接通过 Web 升级**到本项目固件。刷写前应备份设备实际存在的 BL2、FIP、factory / bdinfo 等关键分区，并验证恢复方式。Release 附带的 BL2 仅供匹配引导链的专业恢复场景使用；Open / Closed 的 BL2 不能仅凭芯片型号判断可互换。

具体准备、风险及实机验收项目见 [验证与恢复](docs/VALIDATION.md)。未完成这些检查前，不建议在生产环境使用。

## 项目文件

- [Config](Config) — 设备及软件包配置
- [Scripts](Scripts) — 构建、补丁和校验脚本
- [patches](patches) — 设备树、镜像定义和系统文件覆盖
- [构建说明](docs/BUILD.md) — 版本、参数、CI 与维护
- [验证与恢复](docs/VALIDATION.md) — 刷机准备、网络及加速验收

本仓库不提供 NRadio 原厂 SDK 或 5G 模组固件。刷机可能导致设备无法启动或原厂数据丢失，请自行评估风险。
