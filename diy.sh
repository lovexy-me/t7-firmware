#!/bin/bash
set -e
cd src
cat >> feeds.conf.default <<'F'
src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main
src-git passwall https://github.com/Openwrt-Passwall/openwrt-passwall.git;main
F
./scripts/feeds update -a
# newer Go for sing-box / xray / cloudflared
rm -rf feeds/packages/lang/golang
git clone --depth 1 -b 25.x https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang
# prefer passwall_packages versions over feeds/packages duplicates
for p in xray-core sing-box chinadns-ng v2ray-geodata; do rm -rf feeds/packages/net/$p; done
# EasyTier
git clone --depth 1 https://github.com/EasyTier/luci-app-easytier package/easytier-src
# lucky luci (binary kept on overlay, pinned 2.19.5)
git clone --depth 1 https://github.com/gdy666/luci-app-lucky package/lucky-src || true
./scripts/feeds install -a
./scripts/feeds install -a -p passwall_packages -f
./scripts/feeds install -a -p passwall -f
