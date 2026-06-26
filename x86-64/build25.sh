#!/bin/bash
unset http_proxy
unset https_proxy

echo "🔄 正在初始化 25.12.0 原生编译脚本逻辑..."
VERSION="25.12.0"

# 1. 载入 UI 映射进来的自定义包包名
[ -f "shell/apk-custom-packages.sh" ] && source shell/apk-custom-packages.sh

# 2. 写入 repositories.conf 官仓直供源
cat << EOF > repositories.conf
src/gz openwrt_core ./packages
src/gz openwrt_base https://downloads.immortalwrt.org/releases/$VERSION/targets/x86/64/packages
src/gz openwrt_luci https://downloads.immortalwrt.org/releases/$VERSION/packages/x86_64/luci
src/gz openwrt_packages https://downloads.immortalwrt.org/releases/$VERSION/packages/x86_64/packages
src/gz openwrt_routing https://downloads.immortalwrt.org/releases/$VERSION/packages/x86_64/routing
src/gz openwrt_telephony https://downloads.immortalwrt.org/releases/$VERSION/packages/x86_64/telephony
EOF

# 3. 拦截并处理用户传入的自定义 IP 和 拨号信息
mkdir -p files/etc/config
cat << EOF > files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE:-no}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

# 4. 生成 99-custom-settings 网络自适应脚本
mkdir -p files/etc/uci-defaults
cat << 'EOF' > files/etc/uci-defaults/99-custom-settings
#!/bin/sh
if [ -f "/etc/config/custom_router_ip.txt" ]; then
    LAN_IP=$(cat /etc/config/custom_router_ip.txt | tr -d '\r\n ')
else
    LAN_IP="192.168.15.15"
fi

uci set network.lan.proto='static'
uci set network.lan.ipaddr="$LAN_IP"
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.gateway='192.168.15.1'
uci del_list network.lan.dns='192.168.15.1' 2>/dev/null
uci add_list network.lan.dns='192.168.15.1'
uci add_list network.lan.dns='114.114.114.114'
uci set dhcp.lan.ignore='1'

if [ -f "/etc/config/pppoe-settings" ]; then
    . /etc/config/pppoe-settings
    if [ "$enable_pppoe" = "yes" ] && [ -n "$pppoe_account" ] && [ -n "$pppoe_password" ]; then
        uci set network.wan.proto='pppoe'
        uci set network.wan.username="$pppoe_account"
        uci set network.wan.password="$pppoe_password"
        uci set network.wan.peerdns='1'
    fi
fi

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

# 5. 组装基础包和四大金刚
PACKAGES="base-files netifd luci-compat autocore curl openssh-sftp-server luci-i18n-filemanager-zh-cn luci-i18n-package-manager-zh-cn luci-i18n-ttyd-zh-cn luci-theme-argon"
PACKAGES="$PACKAGES luci-app-openclash luci-app-adguardhome luci-app-diskman luci-app-samba4 luci-i18n-samba4-zh-cn luci-app-passwall luci-i18n-passwall-zh-cn luci-ssl"

# 合并 UI 动态追加的外部插件 (如商店)
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-app-docker dockerd luci-i18n-docker-zh-cn"
fi

# 6. OpenClash 内核云端全量集成
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "🎯 正在下载 OpenClash 高级内核与规则集..."
    mkdir -p files/etc/openclash/core
    wget -qO- "https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64-v1.tar.gz" | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
fi

# 7. 第三方本地离线包清洗解压调用
if [ -f "shell/apk-prepare-packages.sh" ]; then
    echo "🧩 正在整理 extra-packages 中的离线包到 packages 目录..."
    /bin/bash shell/apk-prepare-packages.sh
fi

echo "🔄 刷新本地 APK 包管理器索引..."
make package_index

echo "🚀 开始执行大底座全磁盘格式组装..."
[ -z "$PROFILE" ] && PROFILE=2048
make image -j1 PROFILE="generic" FILES="files" ROOTFS_PARTSIZE=$PROFILE PACKAGES="$PACKAGES"

if [ $? -ne 0 ]; then
    echo "❌ 错误: 固件底层拼装失败!"
    exit 1
fi

# 8. 强力后置清理
OUT_PATH="bin/targets/x86/64"
[ ! -d "$OUT_PATH" ] && OUT_PATH="bin/targets/x86_64/generic"
find "$OUT_PATH" -type f ! -name "*ext4-combined-efi.img.gz" -delete
rm -rf "$OUT_PATH/packages" "$OUT_PATH/*.manifest" "$OUT_PATH/*.sha256sums"
echo "✅ 瘦身完成，已保留唯一目标文件！"
