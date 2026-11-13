# proxyguard-hark

Fork of codeberg.org/eduVPN/proxyguard at tag v2.1.1.

Change: the client sets SO_RCVBUF 4 MiB on its local UDP socket (client.go Setup), so WireGuard bursts are not dropped
(UDP RcvbufErrors) while the TCP/TLS side stalls. The kernel caps it at net.core.rmem_max, so raise that on the host
(PVE host for LXC containers), e.g. net.core.rmem_max=8388608.

Trade-off: drops become queueing delay. Built by .github/workflows/proxyguard-hark.yml into a prerelease
proxyguard-hark-<run_id> (static linux amd64/arm64, xz).

## hark.2 (2026-11-13, server side)
- proxyguard-server logs every tunnel: `tunnel #N open` and `tunnel #N closed after <dur>: <reason>`
  (EOF / 60 s reader timeout / error). The client address is only logged with `-logip`.
- Server UDP socket to WireGuard: SO_RCVBUF/SO_SNDBUF 4 MiB (capped by net.core.rmem_max/wmem_max).
- Hijacked TCP connection: the HTTP server's 10 s read/write deadlines are cleared explicitly.
- Wire protocol unchanged: works with the 2.0.x/2.1.x clients and servers.
