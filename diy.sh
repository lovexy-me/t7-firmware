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
git -C /tmp/owp sparse-checkout set net/cloudflared net/zerotier
cp -r /tmp/owp/net/cloudflared feeds/packages/net/
# cloudflared: bump to latest release
sed -i -e 's/^PKG_VERSION:=.*/PKG_VERSION:=2026.10.7/' -e 's/^PKG_RELEASE:=.*/PKG_RELEASE:=1/' \
  -e 's/^PKG_HASH:=.*/PKG_HASH:=d268031cb8906675b6b6353f18a007e6fc028f170094c5ac9220493bc8147016/' feeds/packages/net/cloudflared/Makefile
# ZeroTier 1.16.2: keep immortalwrt packaging (init/config used by luci-app-zerotier), take version + patches from openwrt master
ZT=feeds/packages/net/zerotier
sed -i -e 's/^PKG_VERSION:=.*/PKG_VERSION:=1.16.2/' -e 's/^PKG_RELEASE:=.*/PKG_RELEASE:=1/' \
  -e 's/^PKG_HASH:=.*/PKG_HASH:=2c607f573c6e38815433af289d364a689a203b18b51125f06c4472014d0657f0/' $ZT/Makefile
grep -q 'ZT_NONFREE' $ZT/Makefile || sed -i 's/ZT_SSO_SUPPORTED=0 \\/ZT_SSO_SUPPORTED=0 \\\n\tZT_NONFREE=0 \\/' $ZT/Makefile
rm -rf $ZT/patches && cp -r /tmp/owp/net/zerotier/patches $ZT/
grep -E '^PKG_(VERSION|HASH)|ZT_' $ZT/Makefile
# EasyTier
git clone --depth 1 https://github.com/EasyTier/luci-app-easytier package/easytier-src
# lucky 2.27.2 + luci (sirpdboy, binary arm64 fetched at build time)
git clone --depth 1 -b v2.27.2 https://github.com/sirpdboy/luci-app-lucky package/lucky-src
LI=package/lucky-src/lucky/files/lucky.init
# keep the existing config dir; don't let the init rewrite the admin port or cancel the safe URL
sed -i -e 's|^CONFDIR=.*|CONFDIR=/etc/config/lucky.daji|' -e '/-setconf -key/d' -e '/-rCancelSafeURL/d' $LI
sed -i -e '/^    if \[ -z "\$SafeURL" \] ; then$/,/^    fi$/d' $LI
sed -i "s|option configdir '/etc/lucky'|option configdir '/etc/config/lucky.daji'|" package/lucky-src/lucky/files/lucky.config
# lucky 2.27 admin is HTTPS-only (self-signed): LuCI iframe must use https, plus a new-tab button to accept the cert
sed -i "s|option ssl '0'|option ssl '1'|" package/lucky-src/lucky/files/lucky.config
LJ=package/lucky-src/luci-app-lucky/htdocs/luci-static/resources/view/lucky/lucky.js
sed -i "s#container.appendChild(iframe);#container.appendChild(E('p',{'id':'lucky-newtab','style':'margin:.5em 0'},[E('a',{'href':buttonUrl,'target':'_blank','class':'btn cbi-button'},_('Open Lucky in new tab'))]));container.appendChild(iframe);#" $LJ
grep -q lucky-newtab $LJ || { echo "lucky.js patch failed"; exit 1; }
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/97-lucky-migrate <<'U'
#!/bin/sh
# gdy666 layout (anonymous section) -> sirpdboy layout (named section lucky.lucky)
# LuCI app hardcodes /etc/lucky; point it at the kept config dir
[ -d /etc/config/lucky.daji ] && [ ! -e /etc/lucky ] && ln -s /etc/config/lucky.daji /etc/lucky
uci -q get lucky.lucky >/dev/null && [ -z "$(uci -q get lucky.lucky.ssl)" ] && { uci set lucky.lucky.ssl=1; uci commit lucky; }
uci -q get lucky.lucky >/dev/null && exit 0
en=$(uci -q get lucky.@lucky[0].enabled)
while uci -q delete lucky.@lucky[0]; do :; done
uci set lucky.lucky=lucky
uci set lucky.lucky.enabled="${en:-1}"
uci set lucky.lucky.logger=1
uci set lucky.lucky.port=16601
uci set lucky.lucky.configdir=/etc/config/lucky.daji
uci set lucky.lucky.ssl=1
uci commit lucky
exit 0
U
./scripts/feeds update -i
./scripts/feeds install -a -p passwall_packages -f
./scripts/feeds install -a -p passwall -f
./scripts/feeds install -a
