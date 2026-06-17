#!/bin/bash
# XanMod 自定义内核一键安装 + 网络调优
# 用法: curl -fsSL https://raw.githubusercontent.com/huabanmao168/xanmod-kernel-build/main/install.sh | bash

set -e

REPO="huabanmao168/xanmod-kernel-build"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()      { printf "${GREEN}  ✅ %s${NC}\n" "$*"; }
warn()    { printf "${YELLOW}  ⚠️  %s${NC}\n" "$*"; }
die()     { printf "${RED}  ❌ %s${NC}\n" "$*"; exit 1; }
section() { printf "\n${CYAN}━━━ %s ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n" "$*"; }

printf "${CYAN}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║     XanMod 内核安装 + 网络极限调优           ║"
echo "  ╚══════════════════════════════════════════════╝"
printf "${NC}\n"

# ═══════════════════════════════════════════════════════
section "1/3  内核安装"
# ═══════════════════════════════════════════════════════

printf "  → 查询最新 Release...\n"
RELEASE_JSON=$(curl -sf "https://api.github.com/repos/${REPO}/releases/latest") \
  || die "无法访问 GitHub API，Release 可能还在构建中"

TAG=$(echo "$RELEASE_JSON" | grep -oP '"tag_name":\s*"\K[^"]+')
[ -z "$TAG" ] && die "未找到 Release，请先触发 GitHub Actions 编译"
printf "  → 版本: ${GREEN}%s${NC}\n" "$TAG"

DEB_URL=$(echo "$RELEASE_JSON" \
  | grep -oP '"browser_download_url":\s*"\K[^"]+linux-image[^"]+\.deb' | head -1)
[ -z "$DEB_URL" ] && die "未找到 linux-image .deb"

HEADERS_URL=$(echo "$RELEASE_JSON" \
  | grep -oP '"browser_download_url":\s*"\K[^"]+linux-headers[^"]+\.deb' | head -1)

printf "  → 下载 %s\n" "$(basename "$DEB_URL")"
wget -q --show-progress -O "$TMP_DIR/linux-image.deb" "$DEB_URL"

if [ -n "$HEADERS_URL" ]; then
  printf "  → 下载 %s\n" "$(basename "$HEADERS_URL")"
  wget -q --show-progress -O "$TMP_DIR/linux-headers.deb" "$HEADERS_URL"
fi

dpkg -i "$TMP_DIR"/linux-*.deb
update-grub 2>/dev/null || grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null \
  || warn "grub 更新失败，请手动确认"
ok "内核 $TAG 安装完成，重启后生效"

# ═══════════════════════════════════════════════════════
section "2/3  系统限制"
# ═══════════════════════════════════════════════════════

cat > /etc/security/limits.d/99-xanmod.conf << 'EOF'
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
* soft nproc  65535
* hard nproc  65535
EOF
ok "文件描述符上限 → 1048576"

# ═══════════════════════════════════════════════════════
section "3/3  sysctl 调优"
# ═══════════════════════════════════════════════════════

# conntrack 模块必须先加载，否则后面的 nf_conntrack_* 参数被内核忽略
modprobe nf_conntrack 2>/dev/null || true
echo "nf_conntrack" > /etc/modules-load.d/xanmod-conntrack.conf

cat > /etc/sysctl.d/99-xanmod.conf << 'EOF'
# ── 文件系统 ──────────────────────────────────────────
fs.file-max                          = 10485760
fs.inotify.max_user_instances        = 1024
fs.inotify.max_user_watches          = 524288

# ── 内存 ──────────────────────────────────────────────
vm.swappiness                        = 5
vm.min_free_kbytes                   = 65536
vm.overcommit_memory                 = 1

# ── 网络核心 ──────────────────────────────────────────
net.core.somaxconn                   = 65535
net.core.netdev_max_backlog          = 500000
net.core.netdev_budget               = 1200
net.core.netdev_budget_usecs         = 12000
net.core.rps_sock_flow_entries       = 32768
net.core.rmem_default                = 262144
net.core.rmem_max                    = 67108864
net.core.wmem_default                = 262144
net.core.wmem_max                    = 67108864
net.core.optmem_max                  = 262144

# ── TCP 缓冲区 ────────────────────────────────────────
net.ipv4.tcp_rmem                    = 4096 262144 33554432
net.ipv4.tcp_wmem                    = 4096 262144 33554432
net.ipv4.tcp_mem                     = 2097152 3145728 6291456

# ── TCP 拥塞 / 性能 ───────────────────────────────────
net.ipv4.tcp_congestion_control      = bbr
net.core.default_qdisc               = fq
net.ipv4.tcp_fastopen                = 3
net.ipv4.tcp_slow_start_after_idle   = 0
net.ipv4.tcp_notsent_lowat           = 131072
net.ipv4.tcp_autocorking             = 0
net.ipv4.tcp_no_metrics_save         = 1
net.ipv4.tcp_mtu_probing             = 1
net.ipv4.tcp_tw_reuse                = 1
net.ipv4.tcp_ecn                     = 2

# ── TCP 超时 / 队列 ───────────────────────────────────
net.ipv4.tcp_fin_timeout             = 15
net.ipv4.tcp_keepalive_time          = 600
net.ipv4.tcp_keepalive_intvl         = 60
net.ipv4.tcp_keepalive_probes        = 3
net.ipv4.tcp_max_syn_backlog         = 65535
net.ipv4.tcp_max_tw_buckets          = 2000000
net.ipv4.tcp_max_orphans             = 524288
net.ipv4.tcp_syncookies              = 1
net.ipv4.tcp_syn_retries             = 3
net.ipv4.tcp_synack_retries          = 3
net.ipv4.tcp_window_scaling          = 1
net.ipv4.tcp_timestamps              = 1

# ── 端口 ──────────────────────────────────────────────
net.ipv4.ip_local_port_range         = 1024 65535
# soga 下游端口段保留，防止内核出口端口复用导致 bind EADDRINUSE
net.ipv4.ip_local_reserved_ports     = 11100-11399,30003

# ── Cloudflare TCP collapse（自编内核生效）────────────
net.ipv4.tcp_collapse_max_bytes      = 6291456

# ── UDP ───────────────────────────────────────────────
net.ipv4.udp_mem                     = 786432 1048576 1572864
net.ipv4.udp_rmem_min                = 16384
net.ipv4.udp_wmem_min                = 16384

# ── IPv6 / 转发 ───────────────────────────────────────
net.ipv6.conf.all.disable_ipv6       = 1
net.ipv6.conf.default.disable_ipv6  = 1
net.ipv4.ip_forward                  = 1

# ── 连接追踪（表满则新连接报错，代理必须）────────────
net.netfilter.nf_conntrack_max                      = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established  = 600
net.netfilter.nf_conntrack_tcp_timeout_time_wait    = 30
net.netfilter.nf_conntrack_udp_timeout              = 30
net.netfilter.nf_conntrack_udp_timeout_stream       = 60

# ── ARP 缓存 ──────────────────────────────────────────
net.ipv4.neigh.default.gc_thresh1    = 4096
net.ipv4.neigh.default.gc_thresh2    = 8192
net.ipv4.neigh.default.gc_thresh3    = 16384
EOF

sysctl -p /etc/sysctl.d/99-xanmod.conf 2>/dev/null | grep -v "^#" || warn "部分参数需重启后生效"

# conntrack 参数 sysctl -p 时模块可能刚加载，补写一次确保生效
sysctl -w net.netfilter.nf_conntrack_max=1048576 2>/dev/null || true
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=600 2>/dev/null || true
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_time_wait=30 2>/dev/null || true
sysctl -w net.netfilter.nf_conntrack_udp_timeout=30 2>/dev/null || true
sysctl -w net.netfilter.nf_conntrack_udp_timeout_stream=60 2>/dev/null || true
ok "sysctl 写入完成"

# ── initcwnd / initrwnd ───────────────────────────────
NIC=$(ip route | awk '/^default/{print $5; exit}')
GW=$(ip route  | awk '/^default/{print $3; exit}')
if [ -n "$GW" ]; then
  ip route change default via "$GW" dev "$NIC" initcwnd 64 initrwnd 64 2>/dev/null \
    && ok "initcwnd / initrwnd = 64"
  RC=/etc/rc.local
  grep -q 'initcwnd 64' "$RC" 2>/dev/null \
    || echo "ip route change default via $GW dev $NIC initcwnd 64 initrwnd 64" >> "$RC"
  chmod +x "$RC" 2>/dev/null || true
fi

# ── NIC ring buffer ───────────────────────────────────
if [ -n "$NIC" ] && command -v ethtool &>/dev/null; then
  # virtio-net 硬限: rx max=1024, tx max=256
  ethtool -G "$NIC" rx 1024 tx 256 2>/dev/null && ok "NIC ring buffer rx=1024 tx=256 (virtio max)"
fi

# ── fq：小包优先 ──────────────────────────────────────
if [ -n "$NIC" ]; then
  tc qdisc replace dev "$NIC" root fq quantum 3028 low_rate_threshold 4Mbit 2>/dev/null \
    && ok "fq low_rate_threshold = 4Mbit ($NIC)"
  grep -q "low_rate_threshold 4Mbit" /etc/rc.local 2>/dev/null \
    || echo "tc qdisc replace dev $NIC root fq quantum 3028 low_rate_threshold 4Mbit" >> /etc/rc.local
fi

# ── XPS 发包绑核 ──────────────────────────────────────
if [ -n "$NIC" ]; then
  NQUEUES=$(ls /sys/class/net/$NIC/queues/ | grep -c '^tx-' 2>/dev/null || echo 1)
  NCPUS=$(nproc)
  for i in $(seq 0 $((NQUEUES - 1))); do
    echo $(printf "%x" $((1 << (i % NCPUS)))) > /sys/class/net/$NIC/queues/tx-$i/xps_cpus 2>/dev/null
  done
  ok "XPS 绑核完成 ($NQUEUES 队列 / $NCPUS 核)"
  grep -q "xps_cpus" /etc/rc.local 2>/dev/null || cat >> /etc/rc.local << RCEOF
for i in \$(seq 0 $((NQUEUES - 1))); do
  echo \$(printf "%x" \$((1 << (i % $NCPUS)))) > /sys/class/net/$NIC/queues/tx-\$i/xps_cpus 2>/dev/null
done
RCEOF
fi
chmod +x /etc/rc.local 2>/dev/null || true

# ═══════════════════════════════════════════════════════
section "验收快照"
# ═══════════════════════════════════════════════════════

FAIL=0
check() {
  local key=$1 expect=$2 val
  val=$(sysctl -n "$key" 2>/dev/null) || true
  if [ -z "$val" ]; then
    printf "  ❌ %-45s (空，内核不支持)\n" "$key"
    FAIL=$((FAIL+1))
  elif [ -n "$expect" ] && [ "$val" != "$expect" ]; then
    printf "  ${YELLOW}⚠️  %-45s %s (期望 %s)${NC}\n" "$key" "$val" "$expect"
  else
    printf "  ${GREEN}✅ %-45s %s${NC}\n" "$key" "$val"
  fi
}

check net.ipv4.tcp_congestion_control      bbr
check net.ipv4.tcp_slow_start_after_idle   0
check net.ipv4.tcp_autocorking             0
check net.ipv4.tcp_no_metrics_save         1
check net.ipv4.tcp_notsent_lowat           131072
check net.core.netdev_max_backlog          ""
check net.core.netdev_budget               ""
check net.ipv4.ip_local_reserved_ports     ""
check net.netfilter.nf_conntrack_max       ""

NIC2=$(ip route | awk '/^default/{print $5; exit}')
if [ -n "$NIC2" ]; then
  CW=$(ip route show default | grep -oP 'initcwnd \K\d+' || echo "未设")
  printf "  ${GREEN}✅ %-45s %s${NC}\n" "initcwnd" "$CW"
  tc qdisc show dev "$NIC2" | grep -q "low_rate_threshold 4Mbit" \
    && printf "  ${GREEN}✅ %-45s %s${NC}\n" "fq low_rate_threshold" "4Mbit" \
    || printf "  ${YELLOW}⚠️  fq low_rate_threshold 未生效${NC}\n"
fi

echo ""
if [ "$FAIL" -gt 0 ]; then
  warn "有 $FAIL 条参数空值（需自编内核或模块支持）"
else
  ok "全部参数写入成功"
fi

printf "\n${CYAN}"
echo "  ╔══════════════════════════════════════════════╗"
printf "  ║  当前内核: %-35s║\n" "$(uname -r)"
printf "  ║  新内核:   %-35s║\n" "$TAG（重启后生效）"
echo "  ║                                              ║"
echo "  ║  重启:  reboot                               ║"
echo "  ║  验证:  uname -r                             ║"
echo "  ║  BBR版: modinfo tcp_bbr | grep version       ║"
echo "  ╚══════════════════════════════════════════════╝"
printf "${NC}\n"
