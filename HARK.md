# proxyguard-hark

Fork of codeberg.org/eduVPN/proxyguard at tag v2.1.1.

Change: the client sets SO_RCVBUF 4 MiB on its local UDP socket (client.go Setup), so WireGuard bursts are not dropped
(UDP RcvbufErrors) while the TCP/TLS side stalls. The kernel caps it at net.core.rmem_max, so raise that on the host
(PVE host for LXC containers), e.g. net.core.rmem_max=8388608.

Trade-off: drops become queueing delay. Built by .github/workflows/proxyguard-hark.yml into a prerelease
proxyguard-hark-<run_id> (static linux amd64/arm64, xz).
