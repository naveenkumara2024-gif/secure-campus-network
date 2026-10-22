# Programmable Secure Campus Network (Containerlab)

A vendor-neutral, fully real emulation of an end-to-end secure campus network with
high availability. It runs real FRR, keepalived, strongSwan and nftables in Linux
containers on WSL2. It adds two novelties: the **Campus Guardian** programmable L2
security plane and a **post-quantum (ML-KEM-768) IPsec** site-to-site VPN.

- Why and how to demo it: [REFINED_PROJECT.md](REFINED_PROJECT.md)
- Live demo runsheet: [docs/demo-runsheet.md](docs/demo-runsheet.md)
- Build spec: [CLAUDE.md](CLAUDE.md)
- Decisions, fallbacks and pinned image tags: [NOTES.md](NOTES.md)

> **Lab only.** Every password, PSK and key in this repo is a deliberately fake lab
> value. Do not reuse any of it outside this lab.

## Quickstart

Run everything inside the **WSL2 Ubuntu** shell, from this folder
(for example `cd /mnt/c/Users/<you>/Downloads/vibecode/CN`).

```bash
make setup     # once: native Docker Engine, containerlab, host tools, kernel modules
               # then open a NEW WSL shell so the docker/clab_admins groups apply
make up        # build local images and deploy the 24-node lab (no sudo needed
               # once you are in the clab_admins group)
make verify    # acceptance matrix V1..V12 (PASS / FAIL / SKIP per row)
make down      # destroy the lab
```

`make up`, `make down` and `make verify` are safe to re-run.

### Docker inside WSL, not Docker Desktop

Containerlab must reach every container's network namespace, so Docker Engine has to
run natively inside the Ubuntu distro. `make setup` installs it. Keep **Docker Desktop's
WSL integration turned off for this distro**; the setup script stops with an error if it
finds it enabled.

### Keep WSL running while the lab is up

WSL stops an idle distro about 15 seconds after its last terminal closes, and that
stops Docker and every lab container. Keep a WSL terminal (or a VS Code WSL window) open
during the demo. If the lab was interrupted, `make verify` reports nodes as not running
and `make up` rebuilds it in about 10 seconds.

To stop WSL from idling out at all, add this to `%UserProfile%\.wslconfig` on Windows,
then run `wsl --shutdown` once:

```ini
[general]
instanceIdleTimeout=-1
```

### Visual layer in VS Code (the "Packet Tracer" view)

1. Open this folder in VS Code **through WSL**: run `code .` from the WSL shell, or use
   *WSL: Connect to WSL* and open the folder there.
2. Install the **Containerlab** extension (publisher *srl-labs*).
3. Open `campus.clab.yml`: **TopoViewer** draws the live topology; nodes turn green when up.
4. Run the command *Containerlab: Install Edgeshark* once. After that, right-click any
   link to capture it live in Wireshark.

### Before the review

The first `make up` pulls about 1 GB of images and builds the edge VPN image.
Do it on good Wi-Fi beforehand. Later deploys work offline.

## Topology at a glance

| Layer | Nodes | Engine |
|---|---|---|
| WAN | isp1, isp2 | Alpine, static routes |
| Edge | edge1, edge2 | Debian trixie: FRR, nftables NAT, strongSwan 6 |
| Core | core1, core2 | FRR 10.4: VLAN bridges + SVIs, OSPF, VRRP, LACP |
| Access | acc1, acc2, acc3, srv-sw | Alpine bridge, RSTP, Campus Guardian |
| Servers (VLAN 40) | dhcp, dns, radius, syslog, ntp, web | Kea, unbound, FreeRADIUS, rsyslog, chrony, nginx |
| Endpoints | pc-student, attacker, phone, pc-faculty, pc-staff, pc-library, pc-guest, branch-host | network-multitool / Alpine |

Access-port map: acc1 has pc-student (VLAN 20), attacker (VLAN 20) and phone (VLAN 100).
acc2 has pc-faculty (VLAN 10) and pc-staff (VLAN 50). acc3 has pc-library (VLAN 30) and
pc-guest (VLAN 60). srv-sw has the six servers. branch-host sits behind edge2 on
172.16.30.0/24.

## Build status

| Milestone | Scope | Status |
|---|---|---|
| M1 | Topology skeleton boots | done |
| M2 | L2 fabric + VLANs | next |
| M3 | Core routing, inter-VLAN, policy | pending |
| M4 | VRRP gateway HA | pending |
| M5 | RSTP + LACP | pending |
| M6 | Campus Guardian plane | pending |
| M7 | Guardian DHCP controller | pending |
| M8 | Post-quantum IPsec | pending |
| M9 | Services | pending |
| M10 | Validation harness + full verify | pending |
