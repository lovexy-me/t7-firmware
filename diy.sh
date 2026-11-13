#!/bin/bash
set -e
. "$(dirname "$0")/pins.env"
cd src
# shallow clone of one pinned commit: pin_clone <url> <sha> <dir>
pin_clone(){ git init -q "$3"; git -C "$3" remote add origin "$1"; git -C "$3" fetch -q --depth 1 origin "$2"; git -C "$3" checkout -q FETCH_HEAD; }
cat >> feeds.conf.default <<F
src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git^${PW_PKGS_SHA}
src-git passwall https://github.com/Openwrt-Passwall/openwrt-passwall.git^${PW_LUCI_SHA}
F
./scripts/feeds update -a
# newer Go for sing-box / xray / cloudflared
rm -rf feeds/packages/lang/golang
pin_clone https://github.com/sbwml/packages_lang_golang $GOLANG_SHA feeds/packages/lang/golang
# prefer passwall_packages versions over feeds/packages duplicates
for p in $(ls feeds/passwall_packages); do rm -rf feeds/packages/net/$p feeds/packages/utils/$p; done
rm -rf feeds/luci/applications/luci-app-passwall*
# newer cloudflared (21.02 feed has 2023.8.1, breaks on new Go)
rm -rf feeds/packages/net/cloudflared
git clone --depth 1 --filter=blob:none --sparse https://github.com/openwrt/packages /tmp/owp
git -C /tmp/owp sparse-checkout set net/cloudflared net/zerotier
git -C /tmp/owp checkout -q $OWPKGS_SHA
cp -r /tmp/owp/net/cloudflared feeds/packages/net/
# cloudflared: bump to latest release
sed -i -e "s/^PKG_VERSION:=.*/PKG_VERSION:=$CLOUDFLARED_VER/" -e 's/^PKG_RELEASE:=.*/PKG_RELEASE:=1/' \
  -e "s/^PKG_HASH:=.*/PKG_HASH:=$CLOUDFLARED_HASH/" feeds/packages/net/cloudflared/Makefile
grep -E '^PKG_(VERSION|HASH)' feeds/packages/net/cloudflared/Makefile
# ZeroTier 1.16.2: keep immortalwrt packaging (init/config used by luci-app-zerotier), take version + patches from openwrt master
ZT=feeds/packages/net/zerotier
sed -i -e 's/^PKG_VERSION:=.*/PKG_VERSION:=1.16.2/' -e 's/^PKG_RELEASE:=.*/PKG_RELEASE:=1/' \
  -e 's/^PKG_HASH:=.*/PKG_HASH:=2c607f573c6e38815433af289d364a689a203b18b51125f06c4472014d0657f0/' $ZT/Makefile
grep -q 'ZT_NONFREE' $ZT/Makefile || sed -i 's/ZT_SSO_SUPPORTED=0 \\/ZT_SSO_SUPPORTED=0 \\\n\tZT_NONFREE=0 \\/' $ZT/Makefile
rm -rf $ZT/patches && cp -r /tmp/owp/net/zerotier/patches $ZT/
grep -E '^PKG_(VERSION|HASH)|ZT_' $ZT/Makefile
# EasyTier
pin_clone https://github.com/EasyTier/luci-app-easytier $EASYTIER_SHA package/easytier-src
# lucky 2.27.2 + luci (sirpdboy, binary arm64 fetched at build time)
git clone --depth 1 -b v2.27.2 https://github.com/sirpdboy/luci-app-lucky package/lucky-src
LI=package/lucky-src/lucky/files/lucky.init
# keep the existing config dir; don't let the init rewrite the admin port or cancel the safe URL
sed -i -e 's|^CONFDIR=.*|CONFDIR=/etc/config/lucky.daji|' -e '/-setconf -key/d' -e '/-rCancelSafeURL/d' $LI
sed -i -e '/^    if \[ -z "\$SafeURL" \] ; then$/,/^    fi$/d' $LI
sed -i "s|option configdir '/etc/lucky'|option configdir '/etc/config/lucky.daji'|" package/lucky-src/lucky/files/lucky.config
# lucky 2.27 admin is HTTPS-only (self-signed); ssl=1 so "Base Setting" opens the web UI over https
sed -i "s|option ssl '0'|option ssl '1'|" package/lucky-src/lucky/files/lucky.config
# drop the "Control panel" iframe menu (blank under self-signed https; Base Setting already opens the web UI)
LM=$(find package/lucky-src/luci-app-lucky -name 'luci-app-lucky.json' | head -1)
python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d.pop("admin/services/lucky/lucky",None);json.dump(d,open(p,"w"),indent=1)' "$LM"
if grep -q '"admin/services/lucky/lucky"' "$LM"; then echo "lucky menu patch failed"; exit 1; fi
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
# shellgate + proxyguard-server ship in the ROM (/usr/libexec/hark, /usr/bin symlinks; binaries copied in by build.yml)
mkdir -p files/etc/init.d
cat > files/etc/init.d/shellgate <<'U'
#!/bin/sh /etc/rc.common
# ROM fallback; an /etc/init.d/shellgate kept in the overlay overrides this one
START=99
STOP=10
USE_PROCD=1
PROG=/usr/bin/shellgate
CONF=/etc/shellgate/env
start_service() {
	[ -x "$PROG" ] || { echo "shellgate: $PROG missing"; return 1; }
	[ -f "$CONF" ] || { echo "shellgate: $CONF missing"; return 1; }
	procd_open_instance
	procd_set_param command "$PROG" --env-file "$CONF"
	procd_set_param env HOME=/root
	procd_set_param respawn 3600 5 5
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_set_param file "$CONF"
	procd_close_instance
}
U
cat > files/etc/init.d/proxyguard-server <<'U'
#!/bin/sh /etc/rc.common
# ROM fallback; an /etc/init.d/proxyguard-server kept in the overlay overrides this one
START=90
STOP=10
USE_PROCD=1
PROG=/usr/bin/proxyguard-server
start_service() {
	[ -x "$PROG" ] || return 1
	procd_open_instance proxyguard-server
	procd_set_param command "$PROG" -listen 127.0.0.1:8444 -to 127.0.0.1:58686
	procd_set_param respawn 3600 5 5
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_close_instance
}
U
chmod 755 files/etc/init.d/shellgate files/etc/init.d/proxyguard-server
mkdir -p files/usr/bin
ln -sf ../libexec/hark/shellgate files/usr/bin/shellgate
ln -sf ../libexec/hark/proxyguard-server files/usr/bin/proxyguard-server

cat > files/etc/uci-defaults/98-hark-shellgate <<'U'
#!/bin/sh
# shellgate and proxyguard-server: the ROM copies live in /usr/libexec/hark. An overlay copy kept by an
# older sysupgrade.conf is replaced by a symlink to the ROM (ln -sf, never rm: rm would leave a whiteout)
# unless the overlay copy is newer than the ROM one.
ver(){ "$1" "$2" 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1; }
# 0 when version $1 >= $2 (numeric x.y.z)
ge(){ awk -v a="$1" -v b="$2" 'BEGIN{n=split(a,x,".");m=split(b,y,".");for(i=1;i<=3;i++){p=x[i]+0;q=y[i]+0;if(p>q)exit 0;if(p<q)exit 1}exit 0}'; }
use_rom(){ # name version-flag
  rom=/usr/libexec/hark/$1; cur=/usr/bin/$1
  [ -x "$rom" ] || return 0
  if [ -L "$cur" ] && [ "$(readlink "$cur")" = "$rom" -o "$(readlink "$cur")" = "../libexec/hark/$1" ]; then :
  elif [ -x "$cur" ]; then
    rv=$(ver "$rom" "$2"); cv=$(ver "$cur" "$2")
    if [ -n "$cv" ] && [ -n "$rv" ] && ! ge "$rv" "$cv"; then
      logger -t hark "$1: overlay $cv newer than ROM $rv, kept"; return 0
    fi
    ln -sf "$rom" "$cur"; logger -t hark "$1: overlay ${cv:-?} -> ROM ${rv:-?}"
  else
    ln -sf "$rom" "$cur"
  fi
  sed -i "\|^/usr/bin/$1\$|d" /etc/sysupgrade.conf 2>/dev/null
}
use_rom shellgate --version
use_rom proxyguard-server -version
for s in shellgate proxyguard-server; do
  [ -x /etc/init.d/$s ] && /etc/init.d/$s enable
done
# rc.d is already enumerated on this first boot, so start them once later
( sleep 60
  pgrep -f /usr/bin/shellgate >/dev/null || /etc/init.d/shellgate start
  netstat -lnt | grep -q ":8444 " || /etc/init.d/proxyguard-server start ) </dev/null >/dev/null 2>&1 &
# firewall defaults: reject anything no zone accepts (zones keep their own policies)
uci -q set firewall.@defaults[0].input=REJECT
uci -q set firewall.@defaults[0].forward=REJECT
uci -q commit firewall
exit 0
U

# haproxy: long-lived ProxyGuard tunnels must not be cut by the 30 s defaults
cat > files/etc/uci-defaults/96-hark-haproxy-timeout <<'U'
#!/bin/sh
C=/etc/haproxy.cfg
M='# hark-pg-timeout'
[ -f "$C" ] || exit 0
grep -q "$M" "$C" && exit 0
grep -qE '^frontend[[:space:]]+proxyguard' "$C" || exit 0
B=$C.hark-bak-$(date +%Y%m%d%H%M%S)
cp -p "$C" "$B" || exit 0
awk -v m="$M" '
  /^(frontend|backend|listen|defaults|global)([[:space:]]|$)/ { sec="" }
  { print }
  /^frontend[[:space:]]+proxyguard/ { print "    timeout client 3m  " m }
  /^backend[[:space:]]+proxyguard/  { print "    timeout server 3m  " m; print "    timeout tunnel 1h  " m }
' "$B" > "$C.new" && mv "$C.new" "$C"
if haproxy -c -f "$C" >/dev/null 2>&1; then
  logger -t hark "haproxy: proxyguard timeouts set (backup $B)"
else
  cp -p "$B" "$C"; logger -t hark "haproxy: check failed, restored $B"
fi
exit 0
U

# ttyd: LAN only
cat > files/etc/uci-defaults/95-hark-ttyd <<'U'
#!/bin/sh
[ -f /etc/config/ttyd ] || exit 0
uci -q get ttyd.@ttyd[0] >/dev/null || uci -q add ttyd ttyd >/dev/null
uci -q set ttyd.@ttyd[0].interface='@lan'
uci -q delete ttyd.@ttyd[0].ipv6
uci -q commit ttyd
exit 0
U
chmod 755 files/etc/uci-defaults/*

./scripts/feeds update -i
./scripts/feeds install -a -p passwall_packages -f
./scripts/feeds install -a -p passwall -f
./scripts/feeds install -a
