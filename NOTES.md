# NOTES.md - build log, decisions, fallbacks, pinned tags

Claude Code records blockers, deviations from CLAUDE.md and verified facts here.

## Environment (verified 2026-10-22)

| Item | Value |
|---|---|
| Host | Windows 11, WSL2 distro `Ubuntu` (Ubuntu 26.04 LTS), systemd on |
| WSL kernel | 6.18.33.2-microsoft-standard-WSL2 |
| WSL resources | 16 vCPU, 7.5 GiB RAM, 2 GiB swap |
| Docker | Engine 29.1.3 (`docker.io` from Ubuntu), native inside WSL |
| Containerlab | 0.81.1 |
| Kernel modules | bridge, 8021q, bonding, xfrm_user, esp4 all load (persisted in `/etc/modules-load.d/campus-lab.conf`) |
| Kernel config | `NF_TABLES_NETDEV=y`, `NETFILTER_INGRESS=y`, `BRIDGE_VLAN_FILTERING=y`, `VETH=y`, `NFT_NAT=y`; `BRIDGE`, `VLAN_8021Q`, `BONDING`, `OPENVSWITCH`, `XFRM_USER`, `INET_ESP` are `=m` and loadable |

## Decisions and deviations

1. **Repo root.** CLAUDE.md section 2 calls the repo `campus-net/`. This folder
   (`vibecode/CN`) already held CLAUDE.md and REFINED_PROJECT.md, so it *is* the repo
   root. `campus_network_documentation.md` (the original Packet Tracer write-up) is kept
   for reference.
2. **Docker Engine native in WSL, not Docker Desktop.** Containerlab needs the
   containers' network namespaces, which Docker Desktop's WSL integration keeps in its
   own VM (https://containerlab.dev/windows/). `scripts/00-setup.sh` installs
   `docker.io` inside Ubuntu and refuses to run if Desktop integration is on for the
   distro. Docker Desktop itself can stay installed.
3. **FRR image registry.** `frrouting/frr:v10.4.0` does not exist on Docker Hub (that
   repo stops at v8.4.1). FRR 10.x is published on Quay, so the cores use
   `quay.io/frrouting/frr:10.4.5`, the latest 10.4 patch release.
4. **Access-switch role map.** The runsheet (REFINED_PROJECT.md section 6) needs
   pc-student and the attacker on acc1 (attacker on port `p2`), so acc1 is the
   student/academic switch: p1 pc-student (VLAN 20), p2 attacker (VLAN 20), p3 phone
   (VLAN 100). acc2: p1 pc-faculty (VLAN 10), p2 pc-staff (VLAN 50). acc3: p1 pc-library
   (VLAN 30), p2 pc-guest (VLAN 60). srv-sw: p1..p6 = dhcp, dns, radius, syslog, ntp, web.
   The original diagram labelled ACC-SW1 "Admin"; in this build that role is acc2.
5. **Extra endpoints.** Besides the five hosts named in CLAUDE.md section 4, the lab adds
   pc-faculty, pc-staff and pc-library so V3 (VLAN 20 to VLAN 30) and every user VLAN have
   a real endpoint.
6. **Extra helper folders.** `nodes/common/node-lib.sh` (shared init helpers) and
   `nodes/isp/` (ISP init) are not in the section 2 layout; they keep the init scripts
   short and avoid duplicated logic.
7. **Interface names.** Containerlab creates the names in `campus.clab.yml` directly:
   cores `eth-peer1/2`, `eth-edge`, `eth-acc1..3`, `eth-srv`; edges `eth-core`,
   `eth-isp`, `eth-branch`; ISPs `eth-edge`, `eth-transit`; access switches
   `eth-up1` (core1), `eth-up2` (core2), `p1..pN`; servers and PCs `eth1`.
   `eth-up1` matches the runsheet's Phase 2 command.
8. **ISP transit.** The two ISPs are joined by an "internet" link so edge1
   (203.0.113.1) and edge2 (198.51.100.1) can reach each other for IPsec. It is not in
   CLAUDE.md section 3; it will use TEST-NET-1 `192.0.2.0/30` (assigned in M3).
9. **Branch LAN placement.** CLAUDE.md section 5.8 makes edge2 the tunnel peer
   protecting `172.16.30.0/24`, so branch-host hangs off edge2 (`eth-branch`).
   M8 must keep campus-to-branch traffic inside the tunnel (edge2 must not advertise
   the branch LAN into OSPF).
10. **Init scripts never exit.** The linux kind defaults to restart policy `always`
    (seen with `docker inspect`; the topology now sets `"no"`, see 12), and a restarted
    container loses all its lab links. Every `init.sh`
    waits for its links (`CLAB_INTFS`, which containerlab sets to the node's link
    count), configures, then hands PID 1 to `tail -f /dev/null`.
11. **Local image name.** The edge image is built as `campus/vpn:latest` by
    `make images`, which `make up` runs first. Docker's build cache makes it a no-op
    when nothing changed.
12. **No auto-restart, health-aware `make up`.** WSL stops an idle distro after
    `instanceIdleTimeout` (default 15 s with no attached session), which stops dockerd.
    This happened once during M1: on the next WSL start Docker restarted all 24 containers
    (policy `always`) with only eth0, so they looked "running" but had no lab links.
    Fix: `restart-policy: "no"` in the topology defaults, so an interrupted lab shows as
    stopped. `make up` checks that every node is running *and* has all its links, and
    redeploys otherwise. Tested by restarting dockerd: V1 FAIL (0/24 running), then
    `make up` rebuilt the lab and V1 PASS. The README tells the user to keep a WSL
    session open or set `instanceIdleTimeout=-1`; the global `.wslconfig` was not changed.
13. **Containerlab without sudo.** The containerlab package installs its binary setuid
    root for the `clab_admins` group. `make setup` adds the WSL user to `docker` and
    `clab_admins`, and the Makefile only prefixes `sudo` for users outside that group.
    (The user's sudo asks for a password, and a `sudo` inside `make` would hang
    non-interactive runs.)
14. **Commits are made by the user.** CLAUDE.md rule 5 asks for a commit after each
    green milestone. The user has asked that Claude make no commits, so from M2 on,
    green milestones are left uncommitted in the working tree for the user to commit.
    (M1 was committed as `153bfdf` before that instruction.)

15. **Core SVI numbering follows CLAUDE.md, not the original write-up.** CLAUDE.md
    section 3 says the VLAN's master core uses `.2` and the backup `.3`. The original
    Packet Tracer document always gave core1 `.2`. This build follows CLAUDE.md, so core2
    is `.2` on VLANs 30, 50, 60 and 99, where it is VRRP master.
16. **Inter-core L3 link on VLAN 200.** `10.10.200.0/30` rides the inter-core trunk as
    SVI `vlan200` (core1 `.1`, core2 `.2`). VLAN 200 is allowed only on that trunk. It
    is not in the section 3 VLAN table because it is a transit VLAN, not a user VLAN.
17. **One VLAN-aware bridge per switch.** Access and core switches each run one
    `br0` with VLAN filtering and no implicit VLAN 1. Access ports are untagged
    members of one VLAN. Trunks are pruned to the VLANs the access switch actually
    has, plus native VLAN 99 untagged (matching the original `native vlan 99`).
    The core-to-core trunk carries every campus VLAN plus VLAN 200.
18. **Access-switch management SVIs.** acc1, acc2, acc3 and srv-sw get `10.10.99.11`
    to `.14` on VLAN 99, with a route to `10.10.0.0/16` via the VLAN 99 VIP. That
    route works from M4 (VRRP); it is there so syslog and NTP can reach the switches
    in M9. eth0 keeps containerlab's management default route.
19. **M2 interim loop avoidance.** Until RSTP and LACP exist (M5), every access
    switch keeps `eth-up2` (to core2) down, and the cores keep `eth-peer2` down, so
    the L2 fabric is a tree. M5 removes both lines.
20. **Bridge netfilter off on switches.** The WSL host loads `br_netfilter`, and
    inside every container `bridge-nf-call-iptables` defaults to 1. That would push
    bridged frames through the cores' nftables policy in M3, so access and core init
    set the three `bridge-nf-call-*` sysctls to 0 in their own namespace.
21. **Endpoint addresses (static until DHCP).** PCs use `.21` in their VLAN, the
    attacker `10.10.20.66`, servers the section 3 IPs, branch-host `172.16.30.10`.
    Every default gateway is the VLAN's VRRP VIP `.1`, which goes live in M4.
22. **Address plan as data.** `nodes/common/addressing.sh` holds the section 3 plan
    and the port/VLAN maps. Every init script and every host script reads it, so no
    address is typed twice.
23. **Derived images (built by `make images`).** `campus/access` is `alpine:3.20` plus
    iproute2, nftables, tcpdump and python3 (BusyBox `ip` has no `bridge vlan`).
    `campus/radius` is `freeradius/freeradius-server:3.2.10` plus iproute2 and ping,
    because the upstream image has neither. FreeRADIUS is now pinned to 3.2.10
    instead of `:latest`.
24. **Ready markers.** Each node touches `/tmp/lab-ready` when its init finishes.
    `make up`, `make redeploy`, `make verify` and `make accept` wait for all of them,
    so `make up && make verify` never tests a half-configured lab.
25. **Containerlab temporary link names.** Containerlab adds each veth under a
    temporary `clab-…` name and then renames it. The link counter ignores those names
    so init never starts configuring before the final interface names exist.
26. **Each VLAN is delivered by its VRRP master (stateful policy with split masters).**
    With core1 master for VLANs 10/20/40/100 and core2 for 30/50/60/99, a plain design
    routes 20 -> 30 through core1 and the reply through core2, so a stateful firewall
    on either core sees only half of each flow. Fix: the master core's SVI is `.2/24`
    and the backup core's SVI is `.3/32`. The backup has no connected route into the
    VLAN, so it routes to it over OSPF via the master. Every routed flow then crosses
    the master of its source VLAN and the master of its destination VLAN, in both
    directions, and both cores see whole flows. Replies sourced from a backup's /32
    SVI use a per-VLAN `ip rule` table and leave directly through that SVI. When VRRP
    moves a VIP (`.1/24`) in M4, the connected /24 and its OSPF advertisement move
    with it. Proven by M3.3: traceroute student to library is core1, core2, host.
27. **Interim static VIP.** Until keepalived arrives (M4), the master core holds the
    gateway VIP `.1/24` as a static second address, so PC gateways work from M3.
28. **OSPF design.** Area 0 on the inter-core VLAN 200 /30 and the two core-edge /30s,
    point-to-point network type, hello 1 s / dead 4 s, every other interface passive.
    Cores redistribute connected routes filtered to `/24`s inside `10.10.0.0/16`, so
    transit /30s and backup /32s never leak. Router IDs are the transit addresses
    (core1 `10.10.200.1`, core2 `10.10.200.2`, edge1 `10.10.211.2`, edge2
    `10.10.212.2`). Each edge has a static default to its ISP and originates it into
    OSPF (E2, metric 10 on both), so each core exits via its nearest edge, and an edge
    whose ISP link dies stops originating.
29. **Inter-VLAN policy (`nodes/core/intervlan.nft`).** Stateful, identical on both
    cores, default drop. Guest: internet only (drops counted in `guest_isolation`).
    DNS for users, voice, management and branch. NTP for users, voice and management.
    Web 80/443 for users and branch. Management VLAN: syslog and RADIUS. Faculty:
    everything internal. Staff Wi-Fi: the whole server farm. Ping between user VLANs
    and the branch. Users: anything at the branch. Internet for everyone but guest.
    Everything else is dropped and counted in `policy_deny`. "Users" means VLANs 10,
    20, 30 and 50. Students therefore reach web and DNS in the server farm but cannot
    ping servers, per CLAUDE.md 5.3 "else deny".
30. **Policy files hold no addresses.** Init generates `/run/campus-defines.nft` from
    `addressing.sh` (`NET_STUDENTS`, `SRV_WEB`, `CAMPUS`, `INFRA`, ...), and every
    `.nft` file includes it.
31. **Edges and ISPs.** Edges run a perimeter filter (`inbound_drop` for unsolicited
    internet connections, `branch_bypass` blocking clear-text campus <-> branch on
    edge2) and PAT (`nat_out`) for campus and branch traffic, excluding traffic to the
    branch (that goes in the tunnel in M8). ISPs know only public addresses. The
    "internet host" `192.0.2.100` is a loopback on both ISPs, reachable via either
    edge.
32. **The lab never touches the real internet.** Containerlab's eth0 default route
    (Docker NAT to the host's real connection) is removed on cores, edges and ISPs, and
    PCs/servers use lab gateways. M3.5 proves `1.1.1.1` is unreachable.
33. **Core sysctls.** `arp_ignore=1` and `arp_announce=2` (an SVI answers ARP only for
    its own address), `rp_filter=0` (routed paths differ per core by design),
    `send_redirects=0`. Edges also run with `rp_filter=0` (IPsec in M8).
34. **Runsheet copy fixes** (`docs/demo-runsheet.md`). Phase 5 pointed the student's
    "allowed (web)" curl at `10.10.40.10`, which is the DHCP server in CLAUDE.md
    section 3; the web server is `10.10.40.15`. Phase 2 kept a student ping running to
    `10.10.40.10`, which the least-privilege policy blocks by design; it now pings the
    student gateway, which crosses the same uplink. `REFINED_PROJECT.md` section 6
    still has both original lines (see Questions for the user).
35. **Web server early.** nginx on `web` starts in M3 because the student -> web policy
    test needs it. The other services still arrive in M9.
36. **Docker's own `table ip nat` in each container** is Docker's embedded-DNS rule
    set, not part of the lab policy. It is harmless and left alone.

## Open items for later milestones

- **M4 / runsheet Phase 1.** Per the containerlab linux-kind docs, a container restarted
  with plain `docker stop` / `docker start` comes back *without* its lab links.
  Containerlab 0.81 has `containerlab stop|start|restart --node` with a "seamless
  dataplane" that keeps the links. M4 will verify which command gives a clean
  failover and recovery and update the runsheet copy if needed.
- **Derived images.** The FRR image has no nftables or keepalived. The alpine and
  FreeRADIUS images lack tools later milestones need (the FreeRADIUS image has no `ip`).
  Thin derived images under `images/` will be added at the milestone that needs them,
  so demos never install packages at boot.
- **M2: iproute2 on access switches.** `alpine:3.20` only has BusyBox `ip` (no `-br`,
  no `bridge vlan`). M2 needs a derived access image with iproute2.
- **M8: IKE daemon.** Debian trixie's `strongswan` package installs `charon-systemd`
  (`/usr/sbin/charon-systemd`), not the classic `charon`. There is no separate `ml`
  plugin; ML-KEM must come from the `openssl` plugin (image has OpenSSL 3.5.7 and
  strongSwan 6.0.1). M8 checks this and records which proposal is negotiated.
- **M5: mstpd** is not packaged for Ubuntu 26.04, Alpine 3.20 or Alpine 3.22. M5
  builds it from source in a derived image, or takes a CLAUDE.md section 7 fallback.
- **M10: scapy** is not packaged for Alpine 3.20 or 3.22 either. The attacker image
  will install it with pip.
- **M4: VRRP replaces the static VIP.** keepalived must own `.1/24` (decision 27 goes
  away). VRRP timers need to be short enough for the "gateway ping loses at most 2
  packets" target in V5.

## Milestone log

### M1 - topology skeleton boots (green, 2026-10-22)

- `containerlab validate`: topology valid, 24 nodes, 29 links.
- `make up` from clean: deploys in about 9 s once images are local; every node logs
  `links ready (N/N)` with N equal to its topology link count.
- `make verify`: `V1 PASS all 24 nodes running, every topology link present`,
  V2 to V12 SKIP (not built yet), exit 0.
- Idempotence checked: `make up` on a healthy lab is a no-op, `make down` twice exits
  0 both times and leaves no containers, `make up` again redeploys cleanly.
- Recovery checked (decision 12): after a dockerd restart, `make verify` fails V1 and
  `make up` restores a passing lab.
- Verified both as root and as the normal WSL user `naveen` (no sudo).
- Linux nodes run privileged; `net.ipv4.ip_forward=1` is set on core, edge and ISP.
- TopoViewer needs VS Code and was not checked from the CLI. The same graph renders
  via `containerlab graph --mermaid` and is kept in `docs/topology.md`.

### M2 - L2 fabric + VLANs (green, 2026-10-22)

`make accept M=M2`: 24 PASS, 0 FAIL, run right after a clean `make down && make up`.

- M2.1 same VLAN, same switch: pc-student reaches the attacker (VLAN 20 on acc1).
- M2.2 all 13 PCs and servers reach both core SVIs of their VLAN (exercises access
  ports, pruned uplink trunks and the inter-core trunk).
- M2.3 all four access-switch management SVIs reach both cores on native VLAN 99.
- M2.4 core1 reaches core2 over the VLAN 200 /30.
- M2.5 every uplink trunk carries exactly its pruned VLAN list with 99 untagged, and
  the access switch, core1 and core2 ends agree.
- M2.6 VLAN isolation: a VLAN 20 port using a VLAN 30 address cannot reach VLAN 30.

`make verify`: V1 PASS, V2 to V12 SKIP. `make up` from clean takes about 18 s
including the readiness wait. No node logs a warning during init.

### M3 - core routing, inter-VLAN routing, policy (green, 2026-10-22)

`make accept M=all`: 47 PASS, 0 FAIL (M2 24 + M3 23), run right after a clean
`make down && make up`. `make verify`: V1 to V4 PASS, V5 to V12 SKIP.

- M3.1 OSPF Full: core1 with core2 and edge1, core2 with core1 and edge2, each edge
  with its core.
- M3.2 each core reaches the other core's VLANs via OSPF over VLAN 200, each core's
  default comes from its own edge, both edges learned all 8 VLAN /24s.
- M3.3 pc-student <-> pc-library both ways; traceroute student -> library is
  `10.10.20.2, 10.10.200.2, 10.10.30.21` (core1, then core2, then host).
- M3.4 guest -> server farm and guest -> student blocked, `guest_isolation` rose on
  core2; student -> web returns HTTP 200; student -> web:8080 times out (dropped) while
  faculty -> web:8080 is refused by the server (allowed through); student -> DHCP server
  and voice -> student blocked, `policy_deny` rose on core1.
- M3.5 pc-student reaches the internet host through edge1 PAT and pc-guest through
  edge2 PAT (`nat_out` rose on each); `1.1.1.1` is unreachable.
- M3.6 a connection attempt from isp1 into the campus is dropped by edge1
  (`inbound_drop` rose).

## Fallbacks taken

None yet.

## Pinned image tags

| Image | Digest | Used by |
|---|---|---|
| `quay.io/frrouting/frr:10.4.5` | `sha256:b0faf7c8f3d8b09aea1e38f77603c745a66dbf5e26ef9718527c2fbb53cc3aed` | base of `campus/core` |
| `campus/core:latest` | local build: FRR 10.4.5 (Alpine 3.22) + nftables 1.1.3, keepalived 2.3.1, tcpdump | core1, core2 |
| `alpine:3.20` | `sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc` | ISPs, dhcp, dns, syslog, ntp, attacker; base of `campus/access` |
| `debian:trixie-slim` | base of `campus/vpn` | edge1, edge2 (built locally) |
| `campus/vpn:latest` | local build: strongSwan 6.0.1, FRR 10.3, nftables 1.1.3, OpenSSL 3.5.7 | edge1, edge2 |
| `nginx:alpine` | `sha256:060849a174666c53439dc7cecbf8f67e225c7cbfb1a44ca97915d9a172a81e6d` | web |
| `freeradius/freeradius-server:3.2.10` | base of `campus/radius` (3.2.10 = what `:latest` was on 2026-10-22) | radius |
| `campus/radius:latest` | local build: FreeRADIUS 3.2.10 + iproute2, iputils-ping | radius |
| `campus/access:latest` | local build: `alpine:3.20` + iproute2 6.9, nftables 1.0.9, tcpdump, python3 | acc1, acc2, acc3, srv-sw |
| `wbitt/network-multitool:alpine-extra` | `sha256:00bf63b9e033362a4adf138c4b14d92bc6ce52446358fed4da14c2e16e8a64aa` | PCs, phone, branch-host |

## Questions for the user

- **REFINED_PROJECT.md section 6 has two lines that conflict with CLAUDE.md.** Phase 5
  curls `10.10.40.10` as "allowed (web)", but the web server is `10.10.40.15`. Phase 2
  pings `10.10.40.10` from pc-student, which the least-privilege policy blocks. The
  demo copy in `docs/demo-runsheet.md` is fixed (decision 34). Should
  `REFINED_PROJECT.md` get the same two-line fix? Not blocking.
