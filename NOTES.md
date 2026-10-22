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
14. **Branch for commits.** The repo was created fresh in M1, so milestone commits go
    straight to `main`.

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
- **mstpd** is not packaged for Ubuntu 26.04. It is only needed inside the alpine
  access-switch containers; availability there is checked in M5.

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

## Fallbacks taken

None yet.

## Pinned image tags

| Image | Digest | Used by |
|---|---|---|
| `quay.io/frrouting/frr:10.4.5` | `sha256:b0faf7c8f3d8b09aea1e38f77603c745a66dbf5e26ef9718527c2fbb53cc3aed` | core1, core2 |
| `alpine:3.20` | `sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc` | access switches, ISPs, servers, attacker |
| `debian:trixie-slim` | base of `campus/vpn` | edge1, edge2 (built locally) |
| `campus/vpn:latest` | local build: strongSwan 6.0.1, FRR 10.3, nftables 1.1.3, OpenSSL 3.5.7 | edge1, edge2 |
| `nginx:alpine` | `sha256:060849a174666c53439dc7cecbf8f67e225c7cbfb1a44ca97915d9a172a81e6d` | web |
| `freeradius/freeradius-server:latest` | `sha256:cc7fd136e7b03e7b332d94297530318e824a4ecfedbce54562cced723e71e812` | radius |
| `wbitt/network-multitool:alpine-extra` | `sha256:00bf63b9e033362a4adf138c4b14d92bc6ce52446358fed4da14c2e16e8a64aa` | PCs, phone, branch-host |

## Questions for the user

None blocking yet.
