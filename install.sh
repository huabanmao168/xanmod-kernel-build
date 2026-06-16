#!/bin/bash
# XanMod 自定义内核一键安装 + 网络调优
# 适用：高并发 SS 入口机
# 用法: curl -fsSL https://raw.githubusercontent.com/huabanmao168/xanmod-kernel-build/main/install.sh | bash

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { printf "${GREEN}✅ %s${NC}\n" "$*"; }
warn() { printf "${YELLOW}⚠️  %s${NC}\n" "$*"; }
die()  { printf "${RED}❌ %s${NC}\n" "$*"; exit 1; }

echo "=================================================="
echo "  XanMod 网络调优"
echo "=================================================="
echo ""

# ══════════════════════════════════════════════════════
# 1. 系统限制
# ══════════════════════════════════════════════════════
echo "【1/2】系统限制"

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
echo "【2/2】sysctl 调优"

# 加载 conntrack 模块（默认可能未加载，否则 sysctl 报错）
modprobe nf_conntrack 2>/dev/null || true
echo "nf_conntrack" > /etc/modules-load.d/xanmod-conntrack.conf

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
net.ipv4.tcp_rmem = 4096 262144 33554432
net.ipv4.tcp_wmem = 4096 262144 33554432
net.ipv4.tcp_mem = 2097152 3145728 6291456

# ── TCP 性能 ──────────────────────────────────────────
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 131072
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
net.ipv4.tcp_autocorking = 0
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.ip_local_port_range = 1024 65535
# soga 下游 listen 端口段保留，避免内核出口源端口复用导致 bind EADDRINUSE
# EG/HB/KM 三套面板 × 16 国 = 11100-11216，宽预留到 11399；30003 = 单独节点
net.ipv4.ip_local_reserved_ports = 11100-11399,30003

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

# ── initcwnd / initrwnd ───────────────────────────────
GW=$(ip route | awk '/^default/{print $3; exit}')
if [ -n "$GW" ]; then
  ip route change default via "$GW" initcwnd 64 initrwnd 64 2>/dev/null && ok "initcwnd/initrwnd = 64"
  # 持久化（NetworkManager 或 /etc/rc.local）
  RC=/etc/rc.local
  grep -q 'initcwnd 64' "$RC" 2>/dev/null \
    || echo "ip route change default via $GW initcwnd 64 initrwnd 64" >> "$RC"
  chmod +x "$RC" 2>/dev/null || true
fi

# ── NIC 收发环缓冲 ────────────────────────────────────
NIC=$(ip route | awk '/^default/{print $5; exit}')
if [ -n "$NIC" ] && command -v ethtool &>/dev/null; then
  ethtool -G "$NIC" rx 4096 tx 4096 2>/dev/null && ok "NIC ring buffer rx/tx = 4096 ($NIC)"
fi

# ── fq low_rate_threshold（小包优先）─────────────────
if [ -n "$NIC" ]; then
  tc qdisc replace dev "$NIC" root fq quantum 3028 low_rate_threshold 4Mbit 2>/dev/null \
    && ok "fq low_rate_threshold = 4Mbit ($NIC)"
  grep -q "low_rate_threshold 4Mbit" /etc/rc.local 2>/dev/null \
    || echo "tc qdisc replace dev $NIC root fq quantum 3028 low_rate_threshold 4Mbit" >> /etc/rc.local
fi

# ── XPS 发包绑核（配合 RPS 减少跨核 cache miss）──────
if [ -n "$NIC" ]; then
  NQUEUES=$(ls /sys/class/net/$NIC/queues/ | grep -c '^tx-' 2>/dev/null || echo 1)
  NCPUS=$(nproc)
  for i in $(seq 0 $((NQUEUES - 1))); do
    echo $(printf "%x" $((1 << (i % NCPUS)))) > /sys/class/net/$NIC/queues/tx-$i/xps_cpus 2>/dev/null
  done
  ok "XPS 绑核完成 ($NQUEUES 队列 / $NCPUS 核)"
  # 持久化
  grep -q "xps_cpus" /etc/rc.local 2>/dev/null || cat >> /etc/rc.local << RCEOF
for i in \$(seq 0 $((NQUEUES - 1))); do
  echo \$(printf "%x" \$((1 << (i % $NCPUS)))) > /sys/class/net/$NIC/queues/tx-\$i/xps_cpus 2>/dev/null
done
RCEOF
fi
chmod +x /etc/rc.local 2>/dev/null || true

# ══════════════════════════════════════════════════════
echo ""
echo "=================================================="
ok "全部完成！"
echo ""
echo "当前内核: $(uname -r)"
echo ""
echo "  重启:  reboot"
echo "  验证:  uname -r && sysctl net.ipv4.tcp_congestion_control"
echo "  BBR版: modinfo tcp_bbr | grep version"
echo ""

# ── 验收快照 ─────────────────────────────────────────
echo "【验收快照】"
FAIL=0
check() {
  local key=$1 expect=$2
  local val
  val=$(sysctl -n "$key" 2>/dev/null) || true
  if [ -z "$val" ]; then
    echo "  ❌ $key = (空，内核不支持)"
    FAIL=$((FAIL+1))
  elif [ -n "$expect" ] && [ "$val" != "$expect" ]; then
    echo "  ⚠️  $key = $val (期望 $expect)"
  else
    echo "  ✅ $key = $val"
  fi
}
check net.ipv4.tcp_congestion_control bbr
check net.ipv4.tcp_slow_start_after_idle 0
check net.ipv4.tcp_autocorking 0
check net.ipv4.tcp_no_metrics_save 1
check net.ipv4.tcp_notsent_lowat 131072
check net.core.netdev_max_backlog ""
check net.core.netdev_budget ""
check net.ipv4.ip_local_reserved_ports ""
check net.netfilter.nf_conntrack_max ""
echo ""
NIC2=$(ip route | awk '/^default/{print $5; exit}')
if [ -n "$NIC2" ]; then
  CW=$(ip route show default | grep -oP 'initcwnd \K\d+' || echo "未设")
  echo "  initcwnd = $CW"
  tc qdisc show dev "$NIC2" | grep -q "low_rate_threshold 4Mbit" \
    && echo "  ✅ fq low_rate_threshold = 4Mbit" \
    || echo "  ⚠️  fq low_rate_threshold 未生效"
fi
[ "$FAIL" -gt 0 ] && echo "" && warn "有 $FAIL 条参数未写入，检查内核是否支持" || echo "  全部写入成功"
echo "=================================================="
