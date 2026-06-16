#!/bin/bash
# XanMod 自定义内核一键安装脚本
# 用法: curl -fsSL https://raw.githubusercontent.com/huabanmao168/xanmod-kernel-build/main/install.sh | bash

set -e

REPO="huabanmao168/xanmod-kernel-build"
API="https://api.github.com/repos/${REPO}/releases/latest"
TMP_DIR=$(mktemp -d)

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "=== XanMod 自定义内核安装 ==="
echo ""

# 获取最新 release
echo "[1/4] 查询最新版本..."
RELEASE_JSON=$(curl -s "$API")
TAG=$(echo "$RELEASE_JSON" | grep -oP '"tag_name":\s*"\K[^"]+')
echo "      最新版本: $TAG"

# 找 linux-image deb 下载链接
DEB_URL=$(echo "$RELEASE_JSON" | grep -oP '"browser_download_url":\s*"\K[^"]+linux-image[^"]+\.deb')

if [ -z "$DEB_URL" ]; then
    echo "❌ 未找到 linux-image deb 包，请检查 Release 是否构建完成"
    exit 1
fi

echo "[2/4] 下载内核包..."
echo "      $DEB_URL"
wget -q --show-progress -O "$TMP_DIR/linux-image.deb" "$DEB_URL"

echo "[3/4] 安装内核..."
dpkg -i "$TMP_DIR/linux-image.deb"
update-grub 2>/dev/null || true

# 配置 Cloudflare TCP collapse sysctl（重启后生效）
if ! grep -q "tcp_collapse_max_bytes" /etc/sysctl.conf 2>/dev/null; then
    echo "" >> /etc/sysctl.conf
    echo "# Cloudflare TCP: 高负载时跳过 collapse (0=禁用, 推荐 6291456=6MB)" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_collapse_max_bytes = 6291456" >> /etc/sysctl.conf
    echo "      ✅ 已写入 tcp_collapse_max_bytes sysctl"
fi

echo "[4/4] 完成"
echo ""
echo "=== 安装成功 ==="
echo "当前内核: $(uname -r)"
echo "新内核将在重启后生效"
echo ""
echo "重启命令: reboot"
echo "验证命令: uname -r && sysctl net.ipv4.tcp_congestion_control && modinfo tcp_bbr | grep version"
