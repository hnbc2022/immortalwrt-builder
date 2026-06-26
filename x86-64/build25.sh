#!/bin/bash
# ==========================================
# 1. 基础环境与网络准备
# ==========================================
# 纯透明网关模式：不设置任何局部代理变量
unset http_proxy
unset https_proxy

echo "🔄 [第一遍运行] 正在初始化全新编译环境..."

# 终极修复：如果工作流传过来了确切的版本号，直接使用；否则再尝试解析目录名
if [ -n "$VERSION_INPUT" ]; then
    VERSION="$VERSION_INPUT"
else
    # 兼容本地运行：如果目录名包含 rc，能完整抓取类似 25.12.0-rc2 的完整版本
    VERSION=$(basename "$PWD" | sed -r 's/immortalwrt-imagebuilder-(.*)-x86-64.*/\1/')
fi

echo "⚙️ 目标官仓固件版本号: $VERSION"

# ==========================================
# 2. 写入远程源（动态锁定输入的具体 RC 或正式版路径）
# ==========================================
echo "📝 正在写入 repositories.conf 官仓直供源..."
cat << EOF > repositories.conf
src/gz openwrt_core ./packages
src/gz openwrt_base https://downloads.immortalwrt.org/releases/$VERSION/targets/x86/64/packages
src/gz openwrt_luci https://downloads.immortalwrt.org/releases/$VERSION/packages/x86_64/luci
src/gz openwrt_packages https://downloads.immortalwrt.org/releases/$VERSION/packages/x86_64/packages
src/gz openwrt_routing https://downloads.immortalwrt.org/releases/$VERSION/packages/x86_64/routing
src/gz openwrt_telephony https://downloads.immortalwrt.org/releases/$VERSION/packages/x86_64/telephony
EOF

# ✨ 25.12.x apk 包管理器核心：刷新本地索引
echo "🔄 正在更新 apk 软件包源索引..."
make package_index

# ==========================================
# 3. 写入首次启动网络与防火墙设置
# ==========================================
echo "🔧 正在写入首次启动网络设置 (静态IP: 192.168.15.15) ..."
mkdir -p files/etc/uci-defaults

cat << 'EOF' > files/etc/uci-defaults/99-custom-settings
#!/bin/sh
uci set network.lan.proto='static'
uci set network.lan.ipaddr='192.168.15.15'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.gateway='192.168.15.1'
uci del_list network.lan.dns='192.168.15.1' 2>/dev/null
uci add_list network.lan.dns='192.168.15.1'
uci add_list network.lan.dns='114.114.114.114'
uci set dhcp.lan.ignore='1'
uci set firewall.@defaults[0].input='ACCEPT'
uci set firewall.@defaults[0].output='ACCEPT'
uci set firewall.@defaults[0].forward='ACCEPT'
sysctl -w net.bridge.bridge-nf-call-arptables=0
sysctl -w net.bridge.bridge-nf-call-ip6tables=0
sysctl -w net.bridge.bridge-nf-call-iptables=0
uci set uhttpd.main.listen_https='0.0.0.0:443'
uci del_list uhttpd.main.listen_https='[::]:443' 2>/dev/null
uci add_list uhttpd.main.listen_https='[::]:443'
uci set uhttpd.main.rfc1918_filter='0'
uci set uhttpd.main.redirect_https='0'
uci commit network
uci commit dhcp
uci commit firewall
uci commit uhttpd
exit 0
EOF

chmod +x files/etc/uci-defaults/99-custom-settings

# ==========================================
# 4. 开启第一遍单线程稳妥下载拼装
# ==========================================
echo "🚀 [第一遍开荒] 开始从零下载并打包固件..."

[ -z "$PROFILE" ] && PROFILE=2048

PACKAGES="base-files netifd luci-compat autocore luci-app-openclash luci-app-adguardhome luci-app-diskman luci-app-samba4 luci-app-ttyd luci-i18n-samba4-zh-cn luci-theme-argon luci-app-passwall luci-i18n-passwall-zh-cn luci-ssl"

if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-app-docker dockerd luci-i18n-docker-zh-cn"
fi

make image -j1 PROFILE="generic" FILES="files" ROOTFS_PARTSIZE=$PROFILE \
    PACKAGES="$PACKAGES" \
    VMDK_IMAGES= QCOW2_IMAGES= VHDX_IMAGES= VDI_IMAGES= ISO_IMAGES=

if [ $? -ne 0 ]; then
    echo "❌ 错误: 固件底层拼装失败!"
    exit 1
fi

# ==========================================
# 5. 后置清理：🔥 强制只留 ext4-combined 包
# ==========================================
OUT_PATH="bin/targets/x86/64"
[ ! -d "$OUT_PATH" ] && OUT_PATH="bin/targets/x86_64/generic"

echo "🧹 正在按照本地清理逻辑进行碎屑清理..."
find "$OUT_PATH" -type f ! -name "*ext4-combined*.img.gz" -delete
rm -rf "$OUT_PATH/packages" "$OUT_PATH/*.manifest" "$OUT_PATH/*.sha256sums"

# ==========================================
# 6. 输出成果
# ==========================================
echo -e "\n====== 🎉 恭喜！原生云编译顺利通关： ======"
ls -lh $OUT_PATH/*ext4-combined-efi.img.gz
