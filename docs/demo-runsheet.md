<!-- docs/demo-runsheet.md - copy of REFINED_PROJECT.md section 6 for the live demo.
     Keep in sync with REFINED_PROJECT.md. Operational notes that differ from the
     original text are recorded in NOTES.md and called out inline as "Lab note". -->

## 6. END-TO-END DEMONSTRATION SCRIPT

This is your runsheet. Each phase = one pillar, ≤ 3 minutes, with the **command**, the **expected output**, and the **one sentence to say**. Total demo ≈ 20 minutes. Rehearse once; it is deterministic.

> Setup before faculty arrive: `cd campus-net && sudo clab deploy -t campus.clab.yml`, open VS Code TopoViewer, and have three terminals ready (`core1`, `acc1`, `attacker`). Helper `make` targets referenced below are defined in the repo.

---

### PHASE 0 — "Here is the whole campus, and it's real" (2 min)

```bash
sudo clab deploy -t campus.clab.yml       # if not already up
sudo clab inspect -t campus.clab.yml      # table of all nodes, all "running"
```
Then show **TopoViewer** (the green topology graph).

**Say:** *"Every box here is a real Linux host running real FRR, strongSwan and nftables — not a simulation. I can open Wireshark on any link."*

---

### PHASE 1 — High Availability: gateway failover (VRRP) (3 min)

```bash
# A student PC pings its gateway continuously
docker exec -it clab-campus-pc-student ping 10.10.20.1
```
In another terminal, confirm who is master, then **kill the master core**:
```bash
docker exec clab-campus-core1 vtysh -c "show ip ospf neighbor"   # OSPF FULL
docker exec clab-campus-core1 ip -br addr | grep 10.10.20         # VIP lives here
sudo clab-campus  # (shorthand) — or:
docker stop clab-campus-core1                                     # simulate core failure
```
**Expected:** the ping loses **1–2 packets** then continues. VRRP on CORE-SW2 takes over VIP `10.10.20.1`; OSPF reconverges.
```bash
docker exec clab-campus-core2 ip -br addr | grep 10.10.20         # VIP now here
```
Bring it back: `docker start clab-campus-core1` → preempt returns mastership.

**Say:** *"Sub-second gateway failover with zero reconfiguration — this is VRRPv3, the open standard HSRP is modelled on. The PC never knew."*

---

### PHASE 2 — High Availability: link redundancy (RSTP + LACP) (2 min)

```bash
# Access switch has two uplinks (to core1 and core2); RSTP keeps one standby
docker exec clab-campus-acc1 mstpctl showport br0                 # one FORWARDING, one DISCARDING
docker exec clab-campus-pc-student ping 10.10.20.1 &              # to its gateway, across the uplink
docker exec clab-campus-acc1 ip link set eth-up1 down             # cut the active uplink
```
> **Lab note:** the original line pinged `10.10.40.10` (the DHCP server). The
> least-privilege policy (CLAUDE.md 5.3) lets students reach only web and DNS in the
> server farm, so that ping is blocked by design. The gateway ping crosses the same uplink.
**Expected:** RSTP moves the standby uplink to FORWARDING in **< 1 s**; ping continues.
```bash
docker exec clab-campus-core1 cat /proc/net/bonding/bond0 2>/dev/null | grep -A2 "802.3ad"   # LACP aggregated
```
**Say:** *"802.1w rapid spanning tree re-paths around the failed uplink in under a second, and the inter-core trunk is a real 802.3ad LACP bond."*

---

### PHASE 3 — THE NOVELTY, part 1: Campus Guardian under attack (6 min) ★

This is the centrepiece. Run from the **attacker** container on access port `p2` of ACC-SW1. Each sub-step is a classic L2/L3 attack; each is dropped; the counter proves it.

```bash
# Baseline: show all Guardian counters at zero and a legit PC working
docker exec clab-campus-acc1 nft list counters table netdev guardian
docker exec clab-campus-pc-student ping -c2 10.10.20.1            # OK
```

Run the **validation harness** (it fires one of each attack, then asserts drops):
```bash
make attack-demo        # wraps the steps below; or run individually:
```

| Attack | Command (attacker) | Guardian result | Counter |
|---|---|---|---|
| **ARP poisoning** | `validate arpspoof` | victim's ARP cache for the gateway is **unchanged** | `dai_drop++` |
| **Rogue DHCP server** | `validate rogue_dhcp` | victim receives **no** forged lease | `rogue_dhcp++` |
| **MAC flooding** | `validate macflood` | 3rd+ MAC on the port is blocked | `psec_viol++` (≈49) |
| **BPDU / STP hijack** | `validate bpdu` | BPDU dropped at ingress | `bpdu_guard++` |
| **IP source spoofing** | `validate ipspoof` | spoofed-source packet never reaches gateway | `ipsg_drop++` |
| **IPv6 rogue RA** | `validate rogue_ra` | rogue Router Advertisement dropped | `ra_guard++` |
| **DHCP starvation** | `validate dhcp_starve` | flood rate-limited | `dhcp_rate++` (≈80) |

Then show the scoreboard — **this is the money shot**:
```bash
docker exec clab-campus-acc1 nft list counters table netdev guardian
```
```
psec_viol  packets 49     bpdu_guard packets 3     rogue_dhcp packets 3
dhcp_rate  packets 80      ra_guard   packets 3     dai_drop   packets 3
ipsg_drop  packets 4       quar_drop  packets 0
```
And prove the **legit PC never suffered**:
```bash
docker exec clab-campus-pc-student ping -c2 10.10.20.1            # still 0% loss
```

**One-command quarantine** (the response capability):
```bash
docker exec clab-campus-acc1 nft add element netdev guardian quarantine '{ "p2" }'
docker exec clab-campus-attacker ping -c2 10.10.20.1             # 100% loss — isolated
docker exec clab-campus-pc-student ping -c2 10.10.20.1           # still fine — neighbour untouched
docker exec clab-campus-acc1 nft delete element netdev guardian quarantine '{ "p2" }'  # released
```

**Say:** *"One table, hooked before the switch fabric, replaced five Cisco features, driven by live DHCP bindings. Every drop is counted, the legitimate user never noticed, and I isolated the attacker with a single command — then released him. Packet Tracer cannot count a drop, cannot do IPv6 RA-Guard, and cannot quarantine."*

---

### PHASE 4 — THE NOVELTY, part 2: Post-Quantum VPN (4 min) ★

```bash
# Branch host is only reachable across the tunnel
docker exec clab-campus-edge1 swanctl --list-sas                 # show IKEv2 SA, proposal line
```
Look for: `IKE proposal: AES_CBC-256/HMAC_SHA2_256/.../X25519/KE1_MLKEM_768`
```bash
docker exec clab-campus-pc-student ping -c3 172.16.30.10         # reaches branch across tunnel
docker exec clab-campus-edge1 swanctl --list-sas | grep -i bytes # encaps/decaps counters rising
```
Open **Wireshark/Edgeshark** on the `edge1 ↔ edge2` public link and show:
- the `IKE_SA_INIT` → **`IKE_INTERMEDIATE`** → `IKE_AUTH` sequence,
- the fragmented `IKE_INTERMEDIATE` carrying the ~1184-byte ML-KEM key,
- ESP packets after that — fully encrypted.

**Say:** *"This tunnel is quantum-resistant. The classical X25519 handshake is combined with ML-KEM-768 — FIPS 203, standardised 2024. Even a recorded capture can't be decrypted by a future quantum computer. This is a 2026 security posture, and no simulator can represent it."*

---

### PHASE 5 — Segmentation, AAA, monitoring (3 min)

```bash
# Inter-VLAN policy: GUEST (60) cannot reach SERVER-FARM (40); STUDENTS can reach WEB only
docker exec clab-campus-pc-guest   ping -c2 10.10.40.10          # blocked (policy)
docker exec clab-campus-pc-student curl -s http://10.10.40.15    # allowed (web)
docker exec clab-campus-core2 nft list counter inet intervlan guest_isolation   # the guest drop, counted
# AAA: SSH to a core authenticates via RADIUS
docker exec clab-campus-core1 tail -f /var/log/auth.log &        # watch
ssh netadmin@<core1-mgmt>                                        # FreeRADIUS Access-Accept
# Monitoring: every node ships logs + synced time
docker exec clab-campus-syslog tail -n5 /var/log/campus.log      # centralised syslog
docker exec clab-campus-core1 chronyc tracking | head -3         # NTP synced
```
**Say:** *"Strict least-privilege inter-VLAN policy, centralised RADIUS authentication, and every device clock-synced and logging to one collector — the manageability pillar, all real daemons."*

---

### Demo fallback plan (say this only if something breaks)
- If a node is unhealthy: `sudo clab destroy -t campus.clab.yml && sudo clab deploy -t campus.clab.yml` rebuilds in ~30 s.
- If PQ-IKE won't negotiate on the grader's box: show the **classical fallback** SA and explain the one-line proposal change — it demonstrates you understand graceful crypto negotiation.
- Keep a **screen recording** of a clean run (`make record`) on disk as insurance.

---

