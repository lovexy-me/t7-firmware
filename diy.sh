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
git clone --depth 1 -b 27.x https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang
# prefer passwall_packages versions over feeds/packages duplicates
for p in $(ls feeds/passwall_packages); do rm -rf feeds/packages/net/$p feeds/packages/utils/$p; done
rm -rf feeds/luci/applications/luci-app-passwall*
# newer cloudflared (21.02 feed has 2023.8.1, breaks on new Go)
rm -rf feeds/packages/net/cloudflared
git clone --depth 1 --filter=blob:none --sparse https://github.com/openwrt/packages /tmp/owp
git -C /tmp/owp sparse-checkout set net/cloudflared
cp -r /tmp/owp/net/cloudflared feeds/packages/net/
# EasyTier
git clone --depth 1 https://github.com/EasyTier/luci-app-easytier package/easytier-src
# lucky luci (binary kept on overlay, pinned 2.19.5)
git clone --depth 1 https://github.com/gdy666/luci-app-lucky package/lucky-src || true
./scripts/feeds update -i
./scripts/feeds install -a -p passwall_packages -f
./scripts/feeds install -a -p passwall -f
./scripts/feeds install -a
