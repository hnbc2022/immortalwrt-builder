#!/bin/bash
# ==========================================
# 1. 基础环境与网络准备 (对齐 Docker 容器内部路径)
# ==========================================
BASE_DIR="/home/build/immortalwrt"

# 进入容器内挂载的编译建筑工目录
cd "$BASE_DIR" || exit 1

echo "🔄 [云端容器内部] 正在初始化全新编译环境..."

# 提取当前 Image Builder 的固件版本号
VERSION="25.12.0"
echo "?? 当前固件版本号: $VERSION"

# ==========================================
# 2. 写入远程源（锁定 25.12.0 正式版路径）
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

# 如果在前端网页勾选了集成 store 商店，则动态追加
if [ -f "shell/apk-custom-packages.sh" ]; then
    source shell/apk-custom-packages.sh
fi

# ==========================================
# 3. 写入首次启动网络与防火墙设置 (静态IP: 192.168.15.15)
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
# 4. 动态组合包列表
# ==========================================
# 基础核心包与你本地选定的全套核心插件
PACKAGES_LIST="base-files netifd luci-compat autocore luci-app-openclash luci-app-adguardhome luci-app-diskman luci-app-samba4 luci-app-ttyd luci-i18n-samba4-zh-cn luci-theme-argon luci-app-passwall luci-i18n-passwall-zh-cn luci-ssl"

# 根据 GitHub 网页端勾选，决定是否集成 Docker 插件
if [ "$INCLUDE_DOCKER" == "yes" ]; then
    PACKAGES_LIST="$PACKAGES_LIST luci-app-docker dockerd luci-i18n-docker-zh-cn"
fi

# 引入外部可能追加的自定义包（如 App Store）
if [ -n "$CUSTOM_PACKAGES" ]; then
    PACKAGES_LIST="$PACKAGES_LIST $CUSTOM_PACKAGES"
fi

# ==========================================
# 5. 执行多线程并发拼装 (在 Docker 内部工具齐备，绝不报错)
# ==========================================
echo "🚀 建筑工开始并发打包固件..."
# 对齐规避参数：拦截多余镜像，只把宿主机传入的 $PROFILE（如 2048）赋给分区大小
make image -j$(nproc) PROFILE="generic" FILES="files" ROOTFS_PARTSIZE=$PROFILE \
    PACKAGES="$PACKAGES_LIST" \
    VMDK_IMAGES= QCOW2_IMAGES= VHDX_IMAGES= VDI_IMAGES= ISO_IMAGES=

echo "✅ 容器内部打包流程顺利结束！"
