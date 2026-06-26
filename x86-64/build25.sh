#!/bin/bash
# ==========================================
# 1. 基础环境与网络准备
# ==========================================
unset http_proxy
unset https_proxy

echo "🔄 [第一遍运行] 正在初始化全新编译环境..."
VERSION="25.12.0"
echo "⚙️ 当前固件版本号: $VERSION"

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

echo "🔄 正在更新 apk 软件包源索引..."
make package_index

# ==========================================
# 3. 写入首次启动网络与防火墙设置 (192.168.15.15)
# ==========================================
echo "🔧 正在写入首次启动网络设置..."
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
# 4. 核心插件列表
# ==========================================
PACKAGES="base-files netifd luci-compat autocore luci-app-openclash luci-app-adguardhome luci-app-diskman luci-app-samba4 luci-app-ttyd luci-i18n-samba4-zh-cn luci-theme-argon luci-app-passwall luci-i18n-passwall-zh-cn luci-ssl"

if [ "$INCLUDE_DOCKER" == "yes" ]; then
    PACKAGES="$PACKAGES luci-app-docker dockerd luci-i18n-docker-zh-cn"
fi

# ==========================================
# 5. 执行打包 (让它把所有虚拟机格式全部高高兴兴生成完)
# ==========================================
echo "🚀 [云端开荒] 开始打包全格式固件..."
make image -j1 PROFILE="generic" FILES="files" ROOTFS_PARTSIZE=$PROFILE PACKAGES="$PACKAGES"

if [ $? -ne 0 ]; then
    echo "❌ 错误: 固件底层拼装失败!"
    exit 1
fi

# ==========================================
# 6. 后置清理：🔥 强制除名！非目标 ext4-combined-efi.img.gz 统统轰杀
# ==========================================
OUT_PATH="bin/targets/x86/64"
[ ! -d "$OUT_PATH" ] && OUT_PATH="bin/targets/x86_64/generic"

echo "🧹 发现大量多余磁盘格式，正在执行精准强制瘦身..."
# 排除掉我们唯一需要的 ext4-combined-efi.img.gz，剩下产生的几十个各种格式文件全部连根拔起
find "$OUT_PATH" -type f ! -name "*ext4-combined-efi.img.gz" -delete
rm -rf "$OUT_PATH/packages" "$OUT_PATH/*.manifest" "$OUT_PATH/*.sha256sums"

echo -e "\n====== 🎉 恭喜！全格式依赖顺利跑完，纯正 EXT4 固件在此： ======"
ls -lh $OUT_PATH/*ext4-combined-efi.img.gz
