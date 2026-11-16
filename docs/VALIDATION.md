# 验证与恢复

**状态：未完成实机验收。** 2026-11-13 的 Open 与 Closed 镜像已经完成 CI 构建、DTB 和 rootfs 静态检查；这不覆盖引导、运行稳定性或真实转发性能。

## 刷机前

1. 核实设备确为 NRadio C8-660 / WT9103，检查闪存容量、分区表及 BL2/FIP 与待刷镜像的兼容性。
2. 在原厂系统中确认分区名称，备份 BL2、FIP、factory / bdinfo 等实际存在的引导与校准分区，并将备份复制到设备外。
3. 确认该设备 U-Boot 的真实恢复流程、网口、TFTP 服务端地址及可接受的镜像格式；不得直接套用其他 MT7981 路由器的刷写步骤。
4. 校验 Release 中对应变体的 SHA-256。Open 与 Closed 的 factory、sysupgrade 和 BL2 不得混用。

首次安装与同变体系统升级属于不同流程。原厂 NROS 不能直接通过 Web 升级到本项目。未经验证的引导链或分区写入存在永久丢失校准数据及无法恢复的风险。

## 实机验收

| 检查项 | 验收要求 |
| --- | --- |
| 引导 | 冷启动、重复重启正常；无异常内核日志 |
| 网络 | LAN、2.5 GbE、DHCP、IPv4/IPv6 通信及 LuCI 可用 |
| 无线 | 双频 SSID、加密、MAC/EEPROM 校准、关联和实际吞吐 |
| 蜂窝 | RM520N 识别、SIM 选择、短信、RGMII/IPPT WAN 与断线恢复 |
| 升级 | 同变体 sysupgrade、配置保留/不保留及回退策略分别验证 |
| 加速 | 有线与 Wi-Fi 双路径分别验证实际 PPE/HNAT 命中及软件回退 |

当前预期 RM520N 默认通过 RGMII/IPPT 把 WAN 数据交给 `eth1`。USB 串口和 QMI 驱动存在，不代表 USB/QMI 已承担实际 WAN 数据面。

### 基础诊断

```sh
ubus call network.interface.wan status | jsonfilter -e '@.l3_device'
logread | grep -Ei 'mt76|mt_wifi|hnat|warp|wed|rm520n|qmi'
ip -br link
```

Closed 的 HNAT 检查：

```sh
ip link show rxppd 2>/dev/null || true
logread | grep hnat-detect
test -r /sys/kernel/debug/hnat/hnat_entry && grep -c BIND /sys/kernel/debug/hnat/hnat_entry
```

Open 的 PPE 检查（仅在对应 debugfs 节点存在时使用）：

```sh
for n in /sys/kernel/debug/ppe0/bind /sys/kernel/debug/ppe1/bind; do
  if [ -r "$n" ]; then echo "$n"; cat "$n"; fi
done
```

必须通过同一组新建 TCP/UDP 测试连接核对绑定条目、方向及计数器变化，不能仅以模块已加载、LuCI 页面显示或全局 BIND 数量证明加速生效。

在默认 `eth1` WAN 路径下没有 `rxppd` 可以是正常现象；仅当改用外部 USB/QMI 数据面时，才需要进一步检查 `hnat-detect` 与 `rxppd` 适配。

## 引导文件

现有测试发布中的 Open BL2 附件名为 `mt7981-bl2.bin`，Closed 的为 `mt7981-ddr4-bl2.bin`。两个工作流均从各自源码生成的 DDR4 BL2 产物复制，但名称和来源不同。**不能据此断定两者与原厂 FIP 配套或能够互相替换。**

BL2 / FIP 不属于常规升级文件；没有匹配分区布局、串口日志及恢复方案时，不应刷写。
