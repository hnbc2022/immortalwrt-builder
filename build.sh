#!/bin/bash
# ==========================================
# 1. 进入编译目录
# ==========================================
cd immortalwrt-imagebuilder || exit 1

VERSION="25.12.0"
echo "?? 当前固件版本号: $VERSION"

# ==========================================
# 2. 写入远程源
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

# 强行将网页后台默认登录密码重置为 password
echo -e "password\npassword" | passwd root

uci commit network
uci commit dhcp
uci commit firewall
uci commit uhttpd
exit 0
EOF

chmod +x files/etc/uci-defaults/99-custom-settings

# ==========================================
# 4. 运行官方 Image Builder 拼装
# ==========================================
echo "🚀 开始并发打包固件..."
make image -j$(nproc) PROFILE="generic" FILES="files" ROOTFS_PARTSIZE=2048 \
PACKAGES="base-files netifd luci-compat autocore luci-app-openclash luci-app-adguardhome luci-app-diskman luci-app-samba4 luci-app-docker dockerd luci-app-ttyd luci-i18n-samba4-zh-cn luci-i18n-docker-zh-cn luci-theme-argon luci-app-passwall luci-i18n-passwall-zh-cn luci-ssl"

# ==========================================
# 5. 精准提取：不要再去用 find 强删了，各走各的路，直接把成品复制到一个新目录
# ==========================================
echo "📦 正在提取唯一的成品 efi 固件到独立输出目录..."
SRC_PATH="bin/targets/x86/64"
DIST_PATH="bin_output"

mkdir -p "$DIST_PATH"
cp "$SRC_PATH"/*squashfs-combined-efi.img.gz "$DIST_PATH/"

echo "✅ 成果提取完毕，独立输出目录内容如下："
ls -lh "$DIST_PATH"/*
