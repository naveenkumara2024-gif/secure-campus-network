#!/bin/sh
# nodes/common/addressing.sh - the CLAUDE.md section 3 address plan as data.
#
# Single source of truth for every init.sh and for scripts/*.sh on the host.
# POSIX sh (busybox ash, dash and bash all source it). Never hard-code a lab
# address anywhere else: add it here and look it up.

# ---- Campus VLANs: <id>:<name>:<VRRP master core> --------------------------
CAMPUS_VLANS="10:FACULTY-ADMIN:core1 20:STUDENTS:core1 30:LIBRARY:core2 40:SERVER-FARM:core1
              50:WIFI-STAFF:core2 60:WIFI-GUEST:core2 99:MGMT-NATIVE:core2 100:VOICE:core1"
NATIVE_VLAN=99          # untagged on every trunk (original design: native vlan 99)
CORE_LINK_VLAN=200      # carries the core1<->core2 10.10.200.0/30 L3 link on the inter-core trunk

vlan_ids()    { for v in $CAMPUS_VLANS; do echo "${v%%:*}"; done; }
vlan_name()   { for v in $CAMPUS_VLANS; do [ "${v%%:*}" = "$1" ] && { v="${v#*:}"; echo "${v%%:*}"; return; }; done; }
vlan_master() { for v in $CAMPUS_VLANS; do [ "${v%%:*}" = "$1" ] && { echo "${v##*:}"; return; }; done; }
vlan_subnet() { echo "10.10.$1.0/24"; }      # VLAN n -> 10.10.n.0/24
vlan_vip()    { echo "10.10.$1.1"; }         # VRRP virtual gateway

# Core SVI address: the VLAN's master core uses .2, the backup .3 (CLAUDE.md section 3).
core_svi_ip() { if [ "$(vlan_master "$1")" = "$2" ]; then echo "10.10.$1.2"; else echo "10.10.$1.3"; fi; }

# ---- Point-to-point L3 links (/30) ----------------------------------------
core_link_ip() { case "$1" in core1) echo 10.10.200.1 ;; core2) echo 10.10.200.2 ;; esac; }

# ---- Access layer -----------------------------------------------------------
# access_ports <switch> -> "<port>:<vlan> ..."   (NOTES.md decision 4)
access_ports() {
  case "$1" in
    acc1)   echo "p1:20 p2:20 p3:100" ;;           # pc-student, attacker, phone
    acc2)   echo "p1:10 p2:50" ;;                  # pc-faculty, pc-staff
    acc3)   echo "p1:30 p2:60" ;;                  # pc-library, pc-guest
    srv-sw) echo "p1:40 p2:40 p3:40 p4:40 p5:40 p6:40" ;;  # dhcp dns radius syslog ntp web
  esac
}
# Management SVI of each access switch, on the native VLAN.
access_mgmt_ip() {
  case "$1" in
    acc1) echo 10.10.99.11 ;; acc2) echo 10.10.99.12 ;;
    acc3) echo 10.10.99.13 ;; srv-sw) echo 10.10.99.14 ;;
  esac
}
# VLANs a switch's trunk carries: its access VLANs plus the native VLAN (pruned trunk).
trunk_vlans() { { for pv in $(access_ports "$1"); do echo "${pv#*:}"; done; echo "$NATIVE_VLAN"; } | sort -un; }
# Core downlink interface -> access switch behind it.
CORE_DOWNLINKS="eth-acc1:acc1 eth-acc2:acc2 eth-acc3:acc3 eth-srv:srv-sw"

# ---- Endpoints and servers --------------------------------------------------
# host_addr <node> -> "<ip>/<len> <gateway>". Gateways are the VRRP VIPs.
# PCs are static until DHCP arrives (M7/M9); servers stay static (section 3).
_vh() { echo "10.10.$1.$2/24 10.10.$1.1"; }
host_addr() {
  case "$1" in
    pc-faculty) _vh 10 21 ;;
    pc-student) _vh 20 21 ;;
    attacker)   _vh 20 66 ;;
    pc-library) _vh 30 21 ;;
    dhcp)       _vh 40 10 ;;
    dns)        _vh 40 11 ;;
    radius)     _vh 40 12 ;;
    syslog)     _vh 40 13 ;;
    ntp)        _vh 40 14 ;;
    web)        _vh 40 15 ;;
    pc-staff)   _vh 50 21 ;;
    pc-guest)   _vh 60 21 ;;
    phone)      _vh 100 21 ;;
    branch-host) echo "172.16.30.10/24 172.16.30.1" ;;   # remote branch LAN behind edge2
  esac
}
host_ip() { set -- $(host_addr "$1"); echo "${1%/*}"; }
CAMPUS_HOSTS="pc-faculty pc-student attacker pc-library pc-staff pc-guest phone"
SERVER_HOSTS="dhcp dns radius syslog ntp web"

# ---- Routed core, WAN and branch (M3) ----------------------------------------
CAMPUS_NET=10.10.0.0/16           # every campus VLAN; what the edges NAT
BRANCH_NET=172.16.30.0/24         # remote branch LAN, reachable only through IPsec (M8)
INFRA_NETS="10.10.200.0/30 10.10.211.0/30 10.10.212.0/30"   # core/edge transit links
INTERNET_HOST=192.0.2.100         # "somewhere on the internet": loopback on both ISPs

# Routed interface addresses: <node>:<interface>:<ip/len>.
# ISP transit (192.0.2.0/30, TEST-NET-1) is not in CLAUDE.md section 3 (NOTES.md 8).
P2P_ADDRS="core1:eth-edge:10.10.211.1/30   edge1:eth-core:10.10.211.2/30
           core2:eth-edge:10.10.212.1/30   edge2:eth-core:10.10.212.2/30
           edge1:eth-isp:203.0.113.1/30    isp1:eth-edge:203.0.113.2/30
           edge2:eth-isp:198.51.100.1/30   isp2:eth-edge:198.51.100.2/30
           isp1:eth-transit:192.0.2.1/30   isp2:eth-transit:192.0.2.2/30
           edge2:eth-branch:172.16.30.1/24"
p2p_addr() { for e in $P2P_ADDRS; do case "$e" in "$1:$2:"*) echo "${e##*:}"; return ;; esac; done; }
addr_ip()  { echo "${1%/*}"; }
# net_of 10.10.211.2/30 -> 10.10.211.0/30 (prefix lengths 24..32)
net_of() {
  local ip="${1%/*}" len="${1#*/}" last size
  last="${ip##*.}"; size=$((1 << (32 - len)))
  echo "${ip%.*}.$((last - last % size))/$len"
}
edge_isp()  { echo "isp${1#edge}"; }      # edge1 -> isp1
edge_core() { echo "core${1#edge}"; }     # edge1 -> core1
other_isp() { if [ "$1" = isp1 ]; then echo isp2; else echo isp1; fi; }
# OSPF router IDs: the node's own transit address.
router_id() {
  case "$1" in
    core1|core2) core_link_ip "$1" ;;
    edge1|edge2) addr_ip "$(p2p_addr "$1" eth-core)" ;;
  esac
}
