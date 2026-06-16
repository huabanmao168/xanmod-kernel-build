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
| Cloudflare TCP | ✅ 内置 | ✅ 内置 |
| fullcone NAT | ✅ 内置 | ✅ 内置 |
| FLOWOFFLOAD | ✅ 内置 | ✅ 内置 |
| BBR v3 | ✅ 内置 | ✅ 内置 |

> 补丁全部由 XanMod 源码内置，本仓库只改 config（HZ、指令集）。

## 更新内核版本

改 `config/kernel_version` 里的 `SOURCE_PKG` 版本号，推送自动触发编译。

手动触发最新版：Actions → Run workflow → `use_latest = true`

## 适用机器

需要 CPU 支持 AVX-512（x86-64-v4），已验证：
- Intel Xeon Gold 6132

不确定的话跑：
```bash
grep avx512 /proc/cpuinfo | head -1 && echo "✅ 支持" || echo "❌ 不支持"
```
