#!/bin/bash
# XanMod 自定义内核一键安装 + 网络调优
# 适用：高并发 SS 入口机
# 用法: curl -fsSL https://raw.githubusercontent.com/huabanmao168/xanmod-kernel-build/main/install.sh | bash

set -e

REPO="huabanmao168/xanmod-kernel-build"
TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
die()  { echo -e "${RED}❌ $*${NC}"; exit 1; }

echo "=================================================="
echo "  XanMod 自定义内核安装 + 网络调优"
echo "=================================================="
echo ""

# ══════════════════════════════════════════════════════
# 1. 内核安装
# ══════════════════════════════════════════════════════
echo "【1/3】内核安装"

RELEASE_JSON=$(curl -sf "https://api.github.com/repos/${REPO}/releases/latest") \
  || die "无法访问 GitHub API"

TAG=$(echo "$RELEASE_JSON" | grep -oP '"tag_name":\s*"\K[^"]+')
echo "  最新版本: $TAG"

DEB_URL=$(echo "$RELEASE_JSON" \
  | grep -oP '"browser_download_url":\s*"\K[^"]+linux-image[^"]+\.deb' \
  | head -1)
[ -z "$DEB_URL" ] && die "未找到 linux-image deb，Release 可能还在构建中"

echo "  下载: $(basename "$DEB_URL")"
wget -q --show-progress -O "$TMP_DIR/linux-image.deb" "$DEB_URL"

dpkg -i "$TMP_DIR/linux-image.deb"
update-grub 2>/dev/null || grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || warn "手动确认 grub"
ok "内核 $TAG 安装完成"

# ══════════════════════════════════════════════════════
# 2. 系统限制
# ══════════════════════════════════════════════════════
echo ""
echo "【2/3】系统限制"

cat > /etc/security/limits.d/99-xanmod.conf << 'EOF'
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
* soft nproc  65535
* hard nproc  65535
EOF
ok "文件描述符上限 1048576"

# ══════════════════════════════════════════════════════
# 3. sysctl（合并机器现有调优参数）
# ══════════════════════════════════════════════════════
echo ""
echo "【3/3】sysctl 调优"

cat > /etc/sysctl.d/99-xanmod.conf << 'EOF'
# ── 文件系统 ──────────────────────────────────────────
fs.file-max = 10485760
fs.inotify.max_user_instances = 1024
fs.inotify.max_user_watches = 524288

# ── 内存 ──────────────────────────────────────────────
vm.swappiness = 5
vm.min_free_kbytes = 65536
vm.overcommit_memory = 1

# ── 网络核心 ──────────────────────────────────────────
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 500000
net.core.netdev_budget = 1200
net.core.netdev_budget_usecs = 12000
net.core.rps_sock_flow_entries = 32768
net.core.rmem_default = 262144
net.core.rmem_max = 67108864
net.core.wmem_default = 262144
net.core.wmem_max = 67108864
net.core.optmem_max = 262144

# ── TCP 缓冲区 ────────────────────────────────────────
net.ipv4.tcp_rmem = 4096 262144 67108864
net.ipv4.tcp_wmem = 4096 262144 67108864
net.ipv4.tcp_mem = 2097152 3145728 6291456

# ── TCP 性能 ──────────────────────────────────────────
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_ecn = 2
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_max_orphans = 524288
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.ip_local_port_range = 1024 65535

# ── Cloudflare TCP collapse ───────────────────────────
net.ipv4.tcp_collapse_max_bytes = 6291456

# ── TCP 窗口 ──────────────────────────────────────────
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1

# ── UDP ───────────────────────────────────────────────
net.ipv4.udp_mem = 786432 1048576 1572864
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

# ── IPv6 禁用（机器现有配置）──────────────────────────
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

# ── IP 转发（代理转发必须）────────────────────────────
net.ipv4.ip_forward = 1

# ── 连接追踪（代理高并发必须，表满新连接直接报错）────
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 600
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_udp_timeout = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 60

# ── ARP 缓存（大量不同 IP 访问时防溢出）──────────────
net.ipv4.neigh.default.gc_thresh1 = 4096
net.ipv4.neigh.default.gc_thresh2 = 8192
net.ipv4.neigh.default.gc_thresh3 = 16384
EOF

sysctl -p /etc/sysctl.d/99-xanmod.conf 2>/dev/null | grep -v "^#" || warn "部分参数需重启后生效"
ok "sysctl 写入完成"

# ══════════════════════════════════════════════════════
echo ""
echo "=================================================="
ok "全部完成！"
echo ""
echo "当前内核: $(uname -r)"
echo "新内核:   $TAG（重启后生效）"
echo ""
echo "  重启:  reboot"
echo "  验证:  uname -r && sysctl net.ipv4.tcp_congestion_control"
echo "  BBR版: modinfo tcp_bbr | grep version"
echo "=================================================="
