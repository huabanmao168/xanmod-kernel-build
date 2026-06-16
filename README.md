# XanMod 自定义内核构建仓库

为 SS 高并发入口机定制编译的 XanMod 内核，专注网络转发场景优化。

## 包含补丁

### 网络优化
- **BBR v3** — TCP 拥塞控制（已内置于 XanMod，确保启用）
- **Cloudflare TCP collapse** — 高负载时跳过 TCP collapse 处理，防止高并发 CPU 被拖死
- **nf_tables fullcone NAT** — 完整锥形 NAT 支持
- **xt_FLOWOFFLOAD** — 流量硬件/软件卸载，提升转发吞吐

### 系统优化
- **ClearLinux LIFO accept()** — 高并发连接接入缓存局部性优化
- **ClearLinux rwsem** — 读写锁自旋优化
- **XanMod 调度器延迟调优**
- **XanMod 500Hz 定时器**（原预编译包是 250Hz）
- **XanMod VFS 缓存优化**
- **XanMod 减少 swap 使用**
- **mm 工作集保护** — 防止高并发下内存抖动
- **ZEN dm-crypt 直接加解密** — 加密流量绕过工作队列

### 编译优化
- **LLVM + Polly** — 多面体循环优化
- **x86-64-v4** — AVX-512 指令集（Xeon Gold 6132 支持）

## 修改项（相比预编译包）

| 项目 | 预编译包 | 本仓库 |
|------|---------|--------|
| 定时器频率 | 250Hz | **500Hz** |
| 指令集 | x64v3 | **x64v4 (AVX-512)** |
| Cloudflare TCP | 无 | **有** |
| Fullcone NAT | 无 | **有** |
| FLOWOFFLOAD | 无 | **有** |

## 安装

从 [Releases](https://github.com/huabanmao168/xanmod-kernel-build/releases) 下载最新 `.deb`：

```bash
# 下载
wget https://github.com/huabanmao168/xanmod-kernel-build/releases/latest/download/linux-image-*.deb

# 安装
dpkg -i linux-image-*.deb

# 重启
reboot

# 验证
uname -r
sysctl net.ipv4.tcp_congestion_control
modinfo tcp_bbr | grep version
```

## 更新内核版本

修改 `config/kernel_version` 文件，推送后自动触发编译。

## 手动触发编译

在 GitHub Actions → Build XanMod Kernel → Run workflow，可指定版本号。
