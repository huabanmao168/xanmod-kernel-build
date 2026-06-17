# XanMod 自定义内核

为高并发 SS 入口机定制编译的 XanMod 内核，基于最新 7.0.y 源码。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/huabanmao168/xanmod-kernel-build/main/install.sh | bash
```

安装完重启：
```bash
reboot
```

验证：
```bash
uname -r
sysctl net.ipv4.tcp_congestion_control
modinfo tcp_bbr | grep version
```

## 相比官方预编译包的改动

| 项目 | 官方 | 本仓库 |
|------|------|--------|
| 定时器 | 250Hz | **500Hz** |
| 指令集 | x64v3 | **x64v4 (AVX-512)** |
| 体积 | 全量驱动 ~6300 模块 | **极简服务器 ~500-800 模块** |
| Cloudflare TCP | ✅ 内置 | ✅ 内置 |
| fullcone NAT | ✅ 内置 | ✅ 内置 |
| FLOWOFFLOAD | ✅ 内置 | ✅ 内置 |
| BBR v3 | ✅ 内置 | ✅ 内置 |
| WireGuard | ✅ 内置 | ✅ 内置 |

> 补丁全部由 XanMod 源码内置，本仓库只改 config（HZ、指令集、驱动裁剪）。

## 极简裁剪说明

本内核专为 **KVM VPS 代理网关** 场景编译，关闭了所有无关子系统以缩短编译时间和减小体积：

**保留的：**
- virtio 全家桶（virtio-net / virtio-scsi / virtio-balloon / virtio-console）
- 文件系统：ext4 / fuse / overlayfs / tmpfs
- 网络栈完整：nftables / iptables / conntrack / NAT / FLOWOFFLOAD / fullcone
- 调度器：fq / cake
- 拥塞控制：BBR v3（默认）+ 所有 TCP 拥塞算法
- 隧道：WireGuard / TUN / VETH / Bridge
- 加密：AES-NI / ChaCha20 / SHA / GCM 等

**砍掉的：**
- 🔇 声卡（SOUND/SND 约 760 个选项）
- 🖥️ GPU/显卡（DRM/FB 约 170 个选项）
- 📶 蓝牙 + WiFi + 无线（约 150 个选项）
- 📷 媒体/摄像头/DVB（约 520 个选项）
- 🌡️ 传感器 IIO / HWMON（约 385 个选项）
- 🔌 所有物理网卡驱动（Intel/Realtek/Mellanox 等约 150 个选项）
- 💾 NVMe / 物理 SCSI 控制器
- 📂 不常用文件系统（btrfs / xfs / ntfs / nfs / cifs 等约 160 个选项）
- 🔧 USB gadget / 串口 / GPIO / SPI / MFD / 稳压器 / 电源管理
- 📡 InfiniBand / RDMA / CAN / ISDN / ATM / 业余无线电
- 🖲️ 输入设备 / 触摸屏 / 游戏手柄
- 🏢 平台驱动（Chrome/Dell/HP/ThinkPad）
- 🔐 TPM / KVM host / VFIO
- 💡 LEDS / Watchdog / Firewire / 并口 / PCMCIA

## 编译时间

| 环境 | 全量 config | 极简 config |
|------|------------|------------|
| GitHub Actions (4 vCPU) | >3h 超时 ❌ | **~60-90 分钟** ✅ |
| 自建 runner (16 核) | ~45 分钟 | ~15 分钟 |

## 更新内核版本

改 `config/version` 里的 `SOURCE_VER` 版本号，推送自动触发编译。

手动触发最新版：Actions → Run workflow → `use_latest = true`

## 适用机器

需要 CPU 支持 AVX-512（x86-64-v4），已验证：
- Intel Xeon Gold 6132

不确定的话跑：
```bash
grep avx512 /proc/cpuinfo | head -1 && echo "✅ 支持" || echo "❌ 不支持"
```
