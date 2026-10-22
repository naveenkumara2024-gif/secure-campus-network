# CLAUDE.md — Build Spec: Programmable Secure Campus Network (Containerlab)

This file instructs Claude Code to build, from an empty repo, a vendor-neutral,
fully-real emulation of an **End-to-End Secure Campus Network with High Availability**,
plus its two novelties: the **Campus Guardian** programmable L2 security plane and a
**Post-Quantum IPsec** VPN. The companion `REFINED_PROJECT.md` explains the *why* and the
*demo*; this file is the *how to build it*.

**Target runtime:** WSL2 (Ubuntu 22.04/24.04) + Docker + Containerlab, on the user's Windows laptop.
**Primary deliverable:** `sudo clab deploy -t campus.clab.yml` brings up the entire network, and
`make verify` proves every pillar passes.

---

## 0. Operating rules for Claude Code (read first)

1. **Build incrementally and keep it always-demoable.** Follow the milestones in §5 in order.
   After each milestone, its acceptance test in §6 **must pass** before moving on. A half-built
   lab that demos Phases 0–3 beats a fully-coded lab that doesn't boot.
2. **Everything is a file in the repo.** No manual `docker exec` configuration that isn't also
   written to a committed config file or a startup script. The review must be reproducible.
3. **Verify, don't assume.** After writing any config, run its acceptance test. Report real
   command output, not expectations. If a kernel feature is missing (see §7), use the documented
   fallback — do not silently skip the feature.
4. **This is a defensive security teaching lab.** The validation harness in §5.9 exists to *prove
   the Guardian controls drop malicious frames*. Keep it minimal, clearly labelled, and focused on
   making counters increment and confirming legitimate hosts are unaffected. Do not expand it into
   a general offensive toolkit.
5. **Commit after each green milestone** with a message ending in the attribution lines in §9.
6. **Idempotence:** `make up` / `make down` / `make verify` must be safe to re-run.
7. When something genuinely needs a human decision (e.g. WSL kernel can't load a module even via
   the documented fallback), stop and write the question into `NOTES.md`, then continue with the
   rest.

---

## 1. Environment setup (write as `scripts/00-setup.sh`, make it re-runnable)

```bash
#!/usr/bin/env bash
set -euo pipefail
# Run inside WSL2 Ubuntu. Assumes Docker Desktop (WSL integration) OR native docker is present.
command -v docker >/dev/null || { echo "Install Docker Desktop + enable WSL integration"; exit 1; }
# Containerlab
command -v containerlab >/dev/null || bash -c "$(curl -sL https://get.containerlab.dev)"
# Host tools used by Makefile targets
sudo apt-get update
sudo apt-get install -y iproute2 tcpdump jq make
containerlab version
docker info >/dev/null && echo "setup OK"
```

**Also tell the user (write to `README.md`):**
- Install the **VS Code "Containerlab" extension** (srl-labs) → gives TopoViewer (visual graph) and
  the "Install Edgeshark" command for in-VS-Code Wireshark capture. This is the visual, Packet-Tracer-like layer for the demo.
- First deploy will pull images; do it on good Wi-Fi before the review.

---

## 2. Repository layout (create exactly this)

```
campus-net/
├── CLAUDE.md                      # this file
├── REFINED_PROJECT.md             # explanation + demo script (already written)
├── README.md                      # quickstart + demo runsheet pointer
├── NOTES.md                       # Claude Code writes blockers/decisions here
├── Makefile                       # up/down/verify/attack-demo/record targets
├── campus.clab.yml                # the Containerlab topology (single source of truth)
├── scripts/
│   ├── 00-setup.sh
│   ├── lib.sh                     # shared bash helpers (colour, assert, counter read)
│   └── record.sh                  # optional: screen/asciinema capture of a clean run
├── images/
│   └── vpn/Dockerfile             # strongSwan 6 + ml plugin image (§5.8)
├── nodes/
│   ├── core/                      # CORE-SW1/2: FRR + keepalived + bridges + inter-VLAN policy
│   │   ├── frr.conf.tmpl
│   │   ├── keepalived.conf.tmpl
│   │   ├── daemons
│   │   ├── intervlan.nft
│   │   └── init.sh                # builds VLAN bridges, SVIs, bond; starts frr+keepalived
│   ├── edge/                      # EDGE-R1/2: FRR + NAT + strongSwan
│   │   ├── frr.conf.tmpl
│   │   ├── daemons
│   │   ├── nat.nft
│   │   ├── swanctl.conf.tmpl
│   │   └── init.sh
│   ├── access/                    # ACC-SW1/2/3, SRV-SW: bridge + RSTP + Guardian
│   │   ├── guardian.nft           # the verified ruleset (§5.6)
│   │   ├── guardian-ctl.py        # DHCP-binding controller (§5.7)
│   │   ├── mstpd-start.sh         # RSTP on the bridge
│   │   └── init.sh
│   ├── servers/
│   │   ├── kea-dhcp4.conf          # DHCP (feeds Guardian bindings)
│   │   ├── unbound.conf            # DNS
│   │   ├── freeradius/            # AAA
│   │   ├── rsyslog.conf           # central syslog
│   │   └── chrony.conf            # NTP
│   └── hosts/
│       └── validate.py            # defensive control-verification harness (§5.9)
└── docs/
    └── demo-runsheet.md           # copy of REFINED_PROJECT.md §6 for the live demo
```

---

## 3. Addressing (authoritative — every config must match this)

VLANs, subnets and VRRP VIPs are **identical to the original submission**:

| VLAN | Name | Subnet | VIP | VRRP master | VRID | priority(master/backup) |
|---|---|---|---|---|---|---|
| 10 | FACULTY-ADMIN | 10.10.10.0/24 | 10.10.10.1 | core1 | 10 | 110/100 |
| 20 | STUDENTS | 10.10.20.0/24 | 10.10.20.1 | core1 | 20 | 110/100 |
| 30 | LIBRARY | 10.10.30.0/24 | 10.10.30.1 | core2 | 30 | 110/100 |
| 40 | SERVER-FARM | 10.10.40.0/24 | 10.10.40.1 | core1 | 40 | 110/100 |
| 50 | WIFI-STAFF | 10.10.50.0/24 | 10.10.50.1 | core2 | 50 | 110/100 |
| 60 | WIFI-GUEST | 10.10.60.0/24 | 10.10.60.1 | core2 | 60 | 110/100 |
| 99 | MGMT-NATIVE | 10.10.99.0/24 | 10.10.99.1 | core2 | 99 | 110/100 |
| 100 | VOICE | 10.10.100.0/24 | 10.10.100.1 | core1 | 100 | 110/100 |

L3 p2p links: core1↔core2 `10.10.200.0/30`; core1↔edge1 `10.10.211.0/30`; core2↔edge2 `10.10.212.0/30`;
edge1↔isp1 `203.0.113.0/30`; edge2↔isp2 `198.51.100.0/30`; branch LAN `172.16.30.0/24`.
Core SVI addresses: master core uses `.2`, backup `.3`, VIP `.1` per VLAN.
Containerlab management net: default `172.20.20.0/24` (don't collide with lab subnets).

Static service IPs (VLAN 40): DHCP/Kea `10.10.40.10`, DNS `10.10.40.11`, RADIUS `10.10.40.12`,
Syslog `10.10.40.13`, NTP `10.10.40.14`, Web `10.10.40.15`.

---

## 4. Node → engine decisions (do not substitute without noting in NOTES.md)

| Node role | Base image | Software | Key point |
|---|---|---|---|
| core1, core2 | `frrouting/frr:v10.4.0` (or latest 10.x) | zebra, ospfd + keepalived + nftables | multilayer switch = bridges-per-VLAN + SVIs + routing |
| edge1, edge2 | custom `images/vpn` (Debian trixie + strongSwan 6) + FRR pkgs | FRR, strongSwan 6 `ml`, nftables NAT | PQ-IPsec terminates here |
| acc1/2/3, srv-sw | `alpine:3.20` (has nftables, mstpd, python3, iproute2) | bridge + mstpd (RSTP) + Guardian nft + guardian-ctl.py | Guardian netdev hook on access ports |
| isp1, isp2 | `alpine:3.20` | static route back + "internet" loopback | upstream |
| dhcp | `jonasal/kea` or Debian + `kea-dhcp4-server` | Kea DHCP4 | lease events feed Guardian |
| dns | `alpine` + unbound | unbound | — |
| radius | `freeradius/freeradius-server:latest` | FreeRADIUS | AAA for SSH to cores |
| syslog | `alpine` + rsyslog | rsyslog | central collector |
| ntp | `alpine` + chrony | chrony | time sync |
| web | `nginx:alpine` | nginx | inter-VLAN ACL target |
| pc-student, pc-guest, phone, branch-host, attacker | `wbitt/network-multitool` or `alpine` | ping/curl/python3-scapy | endpoints + validation |

> Pin image tags once they pull successfully; record the working tags in `NOTES.md`.

---

## 5. Build milestones (do in order; each ends green)

### 5.1 M1 — Topology skeleton boots
Write `campus.clab.yml` with **all** nodes and links from §3, using `kind: linux`. Use `binds` to
mount each node's config dir and an `exec`/`cmd` that runs its `init.sh`. Minimal init first (just
bring interfaces up). 
- Containerlab `linux` nodes are **privileged by default** (needed for nft/bridge) — keep it.
- Set `net.ipv4.ip_forward: 1` on core/edge via the `sysctls` key.
- **Accept:** `sudo clab deploy` → `clab inspect` shows every node `running`; TopoViewer draws the graph.

### 5.2 M2 — L2 fabric + VLANs
Access nodes: build a Linux bridge, add access ports as untagged VLAN members (use `bridge vlan`),
trunk uplinks carrying all VLANs. Core nodes: one bridge per VLAN (or a VLAN-filtering bridge) with
an SVI IP (`.2`/`.3`). 
- **Accept:** two PCs in the same VLAN on the same access switch ping each other; a PC pings its
  core SVI `.2`.

### 5.3 M3 — Core routing + inter-VLAN (FRR) + inter-VLAN policy
Enable `ip_forward`; render `frr.conf` (OSPF Area 0 on the p2p links + redistribute connected for
SVIs). Load `intervlan.nft` implementing least-privilege (e.g. GUEST 60 → SERVER-FARM 40 **deny**;
STUDENTS 20 → web `10.10.40.15:80` **allow**, else deny).
- **Accept:** PC in VLAN 20 reaches a PC in VLAN 30 via core routing; `show ip ospf neighbor` on a
  core is `Full` with the other core/edges; guest→server-farm is blocked; student→web works.

### 5.4 M4 — Gateway HA (VRRP via keepalived)
Render `keepalived.conf` with one `vrrp_instance` per VLAN per the §3 table (master/backup split,
preempt on, authentication). VIP `.1` is the PCs' default gateway.
- **Accept:** PC default-routes via `.1`; `docker stop core1` → ping to gateway loses ≤2 packets
  then continues; VIP appears on core2; `docker start core1` → preempt returns it.

### 5.5 M5 — Link HA (RSTP + LACP)
Each access switch has **two** uplinks (core1, core2). Run **mstpd** (`mstpctl`) on the access
bridge for 802.1w so one uplink forwards and one discards. Between core1↔core2 build an **LACP bond**
(mode 802.3ad) carrying the trunk + the `10.10.200.0/30` L3 link.
- **Accept:** `mstpctl showport br0` shows one FORWARDING / one DISCARDING; downing the forwarding
  uplink reconverges in <1s with continuous ping surviving; `/proc/net/bonding/bond0` shows LACP
  aggregated. *(If mstpd unavailable — see §7 — fall back to OVS RSTP or a single active uplink
  with the standby held down, and note it.)*

### 5.6 M6 — Campus Guardian plane (N1) ★
Place this **verified** ruleset at `nodes/access/guardian.nft` and load it in each access node's
`init.sh` with `nft -f`. Parameterise the port list / per-port psec sets per switch.

```nft
table netdev guardian {
    set dai_bind  { typeof iifname . arp saddr ether . arp saddr ip ; flags timeout ; }
    set ipsg_bind { typeof iifname . ether saddr . ip saddr ; flags timeout ; }
    set quarantine { typeof iifname ; }
    set dhcp_rl   { typeof iifname ; size 256 ; flags dynamic,timeout ; timeout 60s ; }
    set psec_p1 { typeof ether saddr ; size 2 ; flags dynamic ; }
    set psec_p2 { typeof ether saddr ; size 2 ; flags dynamic ; }

    counter bpdu_guard {}
    counter psec_viol {}
    counter rogue_dhcp {}
    counter ra_guard {}
    counter dhcp_rate {}
    counter dai_drop {}
    counter ipsg_drop {}
    counter quar_drop {}

    chain access_in {
        type filter hook ingress devices = { "p1", "p2" } priority -200 ; policy accept ;
        iifname @quarantine counter name quar_drop drop
        ether daddr 01:80:c2:00:00:00 counter name bpdu_guard drop
        iifname vmap { "p1" : jump psec_p1, "p2" : jump psec_p2 }
    }
    chain psec_p1 {
        add @psec_p1 { ether saddr } goto l3_checks
        counter name psec_viol drop
    }
    chain psec_p2 {
        add @psec_p2 { ether saddr } goto l3_checks
        counter name psec_viol drop
    }
    chain l3_checks {
        udp sport { 67, 547 } counter name rogue_dhcp drop
        icmpv6 type nd-router-advert counter name ra_guard drop
        udp dport 67 update @dhcp_rl { iifname limit rate over 10/second burst 20 packets } \
            counter name dhcp_rate drop
        ether type arp arp saddr ip 0.0.0.0 accept
        ether type arp iifname . arp saddr ether . arp saddr ip @dai_bind accept
        ether type arp counter name dai_drop drop
        ip saddr 0.0.0.0 udp dport 67 accept
        ether type ip iifname . ether saddr . ip saddr @ipsg_bind accept
        ether type ip counter name ipsg_drop drop
    }
}
```

Notes that make it correct:
- `devices = { ... }` must list that switch's **real access-port interface names** (as seen inside
  the container, e.g. `eth1`,`eth2`). Rename to `p1/p2` via the topology or adjust the set names.
- `priority -200` runs it before the bridge. `policy accept` + explicit `drop`s = default-allow for
  anything not matched (so control traffic flows); every *security* decision is an explicit drop.
- For static devices (servers, phones) without DHCP, pre-seed `dai_bind`/`ipsg_bind` in `init.sh`.
- **Accept:** `nft list ruleset` loads clean; a legit PC pings its gateway; all counters start 0.

### 5.7 M7 — Guardian controller (DHCP → bindings)
`nodes/access/guardian-ctl.py`: subscribe to DHCP lease events and insert/delete the learned
`(iif, mac, ip)` into `dai_bind` and `ipsg_bind` with a timeout = lease time. Two viable sources:
(a) tail Kea's lease file / hook; (b) run the controller on the access node and sniff DHCP ACKs on
the uplink with scapy, extracting `(client-mac, your-ip)` and the ingress port. Prefer (a) if Kea
hooks are easy; (b) is self-contained. Idempotent; logs each binding to syslog.
- **Accept:** a PC set to DHCP gets a lease from Kea; within ~1s its `(port,mac,ip)` appears in both
  sets (`nft list set netdev guardian dai_bind`); its ARP and IP traffic now pass the bind checks.

### 5.8 M8 — Post-Quantum IPsec (N2) ★
`images/vpn/Dockerfile`:
```dockerfile
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      strongswan strongswan-swanctl libcharon-extra-plugins \
      libstrongswan-extra-plugins iproute2 iputils-ping nftables frr \
 && rm -rf /var/lib/apt/lists/*
# Ensure the 'ml' plugin (ML-KEM, FIPS 203) is enabled; openssl plugin (OpenSSL>=3.5) also provides it.
```
`swanctl.conf.tmpl` (edge1 side; mirror on edge2):
```
connections {
  campus-pq {
    version = 2
    local_addrs  = 203.0.113.1
    remote_addrs = 198.51.100.1
    proposals     = aes256-sha256-x25519-ke1_mlkem768, aes256-sha256-modp2048   # PQ first, classical fallback
    local  { auth = psk ; id = edge1 }
    remote { auth = psk ; id = edge2 }
    children {
      net-net {
        local_ts  = 10.10.0.0/16
        remote_ts = 172.16.30.0/24
        esp_proposals = aes256gcm16-x25519-ke1_mlkem768, aes256gcm16-modp2048
        start_action = trap
      }
    }
  }
}
secrets { ike-campus { id-edge1 = edge1 ; id-edge2 = edge2 ; secret = "LabPsk-ChangeMe-2026" } }
```
- **Accept:** `swanctl --initiate --child net-net` then `swanctl --list-sas` shows an established SA
  whose proposal contains `KE1_MLKEM_768`; a campus PC pings `172.16.30.10` across the tunnel;
  encaps/decaps byte counters rise; an Edgeshark capture on the public link shows
  `IKE_SA_INIT → IKE_INTERMEDIATE → IKE_AUTH` then ESP. *(If `ml` negotiation fails on the host,
  the classical fallback SA forms — record which one and why in NOTES.md.)*

### 5.9 M9 — Services (DHCP/DNS/AAA/Syslog/NTP/Web)
Bring up Kea (scopes per VLAN, option routers = VIP), unbound, FreeRADIUS (one test user; cores use
it for SSH login auth with local fallback), rsyslog collector (all nodes `*.* @10.10.40.13`), chrony
(all nodes sync to `10.10.40.14`), nginx.
- **Accept:** PC gets DHCP + resolves a name; SSH to a core authenticates via RADIUS (watch
  `auth.log`); syslog collector shows lines from ≥3 nodes; `chronyc tracking` is synced.

### 5.10 M10 — Validation harness + verify target (defensive)
`nodes/hosts/validate.py` — a **control-verification** tool run from the attacker endpoint. For each
Guardian control it emits exactly one malicious frame of that class and the Makefile then asserts
the matching counter incremented and that a bystander PC still pings. Keep it to these labelled
cases only: `arpspoof, rogue_dhcp, macflood, bpdu, ipspoof, rogue_ra, dhcp_starve`. Each case is a
few scapy lines; the *point* is the drop, not the attack. (Reference implementation logic was
validated already and is summarised in REFINED_PROJECT.md §6 Phase 3.)
- **Accept:** `make attack-demo` runs all cases; `make verify` asserts every counter > 0 after the
  run and that `pc-student` kept 0% loss; quarantine isolates the attacker port and release restores it.

---

## 6. Acceptance / verification matrix (encode in `make verify`)

| ID | Check | Pass condition |
|---|---|---|
| V1 | all nodes up | `clab inspect` all `running` |
| V2 | OSPF | each core/edge `show ip ospf neighbor` all `Full` |
| V3 | inter-VLAN routing | VLAN20 ↔ VLAN30 ping OK |
| V4 | inter-VLAN policy | guest(60)→server(40) **blocked**; student→web **OK** |
| V5 | VRRP failover | stop master → gateway ping loss ≤2, VIP moves, recovers on start |
| V6 | RSTP/LACP | one uplink FORWARDING/one DISCARDING; link-down reconverges <1s; bond LACP up |
| V7 | Guardian loads | ruleset present on every access node, legit ping OK |
| V8 | Guardian drops | after `attack-demo`: psec_viol>0, dai_drop>0, ipsg_drop>0, rogue_dhcp>0, bpdu_guard>0, ra_guard>0, dhcp_rate>0 |
| V9 | bystander safe | pc-student 0% loss throughout V8 |
| V10 | quarantine | quarantined port 100% loss, neighbour OK, release restores |
| V11 | PQ-IPsec | SA established; proposal has `MLKEM`; branch reachable; ESP on wire |
| V12 | services | DHCP lease + DNS resolve + RADIUS auth + syslog + NTP all OK |

`make verify` prints a PASS/FAIL line per row and exits non-zero on any FAIL.

---

## 7. WSL2 gotchas (I checked the stock WSL kernel configs — act on these)

The stock WSL2 kernels (6.6.y and 6.18.y) were inspected. Relevant facts and the design choices
that avoid trouble:

| Kernel feature | Stock WSL state | Consequence / what to do |
|---|---|---|
| `NF_TABLES_NETDEV` | **=y (built-in)** | ✅ Guardian uses the **netdev** family — guaranteed available. This is why Guardian hooks at netdev ingress, not bridge. |
| `NF_TABLES_BRIDGE` | **not set** | ❌ Do **not** write `table bridge ...` rules — they won't load. All L2 filtering stays in `table netdev`. |
| `XFRM_USER`,`INET_ESP` | =m | strongSwan runs **inside the edge containers**; ensure the host has `xfrm_user`/`esp4` loadable or built-in. Policy-based IPsec (above) needs no xfrm *interface*. |
| `XFRM_INTERFACE` | **not set** | ❌ Do **not** use route-based `xfrm` interfaces (`ip link add ipsec0 type xfrm`). Use **policy-based** IPsec with `local_ts`/`remote_ts` (as in §5.8). |
| `BONDING` | =m | May need `modprobe bonding` on the WSL host. If modules aren't loadable, fall back: model the inter-core trunk as a plain veth pair and *describe* it as the aggregated link, or use teamd userspace. Note the choice. |
| `OPENVSWITCH` | =m | OVS RSTP is the *fallback* for M5; primary is userspace **mstpd** (no kernel module). If neither loads, use single-active-uplink fallback. |
| `BRIDGE`,`VETH`,`VLAN_8021Q`,`VXLAN`,`TUN`,`MACVLAN` | present | ✅ core L2 primitives fine. |
| modules VHD | WSL ships limited loadable modules | If `modprobe X` fails for an `=m` feature, prefer the userspace/built-in path above rather than rebuilding the WSL kernel (don't send the user down a custom-kernel rabbit hole before the review). |

General: run `sudo clab` (needs root for netns/nft); if Docker Desktop, ensure WSL integration is on
for the distro. Keep lab subnets off `172.20.20.0/24` (clab mgmt).

---

## 8. Makefile targets (implement these)

```
make setup        # scripts/00-setup.sh
make up           # clab deploy -t campus.clab.yml
make down         # clab destroy -t campus.clab.yml --cleanup
make graph        # clab graph (or remind to use VS Code TopoViewer)
make verify       # run V1..V12, print PASS/FAIL table, exit non-zero on fail
make attack-demo  # run nodes/hosts/validate.py for all Guardian cases, then show counters
make quarantine P=p2 N=acc1   # add/del quarantine element (demo helper)
make record       # optional asciinema/screen capture of a clean verify run
```

---

## 9. Conventions & commit attribution

- Config files are **templates** rendered by `init.sh` from §3 values — never hand-duplicate IPs.
- Every security *drop* has a named counter (observability is part of the novelty).
- Keep lab secrets obviously fake and in one place; note "lab only" in README.
- Commit after each green milestone. **End every commit message with:**

```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013vUen5Dt7vWzxZCwr6FhUn
```

If you open a PR, end its description with:
```
🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_013vUen5Dt7vWzxZCwr6FhUn
```

---

## 10. Definition of done

- `make up && make verify` → all of V1–V12 **PASS** from a clean clone on the user's WSL2.
- TopoViewer shows the full green topology; Edgeshark can capture the ML-KEM handshake.
- `REFINED_PROJECT.md §6` demo runsheet executes end-to-end without edits.
- `NOTES.md` records any fallback taken (bond/RSTP/PQ) and the working pinned image tags.
- Repo is committed with the attribution lines above.

Build in milestone order, test each step for real, and keep it demoable at every commit.
