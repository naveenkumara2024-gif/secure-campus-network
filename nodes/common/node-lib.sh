#!/bin/sh
# nodes/common/node-lib.sh - helpers sourced by every node's init.sh.
#
# POSIX sh only: it runs under busybox ash (Alpine images) and dash/bash (Debian/Ubuntu).
#
# IMPORTANT: an init.sh must never exit non-zero. Containerlab gives linux nodes an
# on-failure restart policy, and a restarted container loses every lab link except eth0.
# So: no `set -e`, log problems, and always finish with keep_alive.

NODE="$(hostname)"

# Address plan (CLAUDE.md section 3 as data).
. /lab/common/addressing.sh

log() { echo "[$NODE] $(date +%H:%M:%S) $*"; }

# Run one config command; on failure log it and carry on (init must never exit).
run() { "$@" || log "WARNING: command failed: $*"; }

# Data-plane interfaces: every Ethernet-type link except lo, the eth0 management
# port, kernel fallback tunnel devices, and the bridges, bonds and VLAN SVIs that
# init scripts create themselves.
data_ifs() {
  for d in /sys/class/net/*; do
    n="${d##*/}"
    # clab-* = temporary veth name containerlab uses before renaming it into place.
    case "$n" in lo|eth0|gretap0|erspan0|ip6gre0|clab-*|*.*|br[0-9]*|bond[0-9]*|vlan[0-9]*) continue ;; esac
    [ -r "$d/type" ] && [ "$(cat "$d/type")" = 1 ] || continue
    if [ -d "$d/bridge" ] || [ -d "$d/bonding" ]; then continue; fi
    echo "$n"
  done
}

# Block until containerlab has plugged in all of this node's links.
# Containerlab starts the container first and adds the veth links afterwards,
# exporting the expected link count as CLAB_INTFS.
wait_for_links() {
  want="${CLAB_INTFS:-}"; t=0; have=0
  while :; do
    have=$(data_ifs | wc -l | tr -d ' ')
    if [ -n "$want" ]; then
      [ "$have" -ge "$want" ] && break
    elif [ "$t" -ge 5 ] && [ "$have" -gt 0 ]; then
      break                      # no hint from containerlab: settle after 5 s
    fi
    if [ "$t" -ge 120 ]; then
      log "WARNING: only $have/${want:-?} links after 120 s, continuing"; break
    fi
    sleep 1; t=$((t + 1))
  done
  log "links ready ($have/${want:-?}): $(data_ifs | tr '\n' ' ')"
}

# Administratively enable every data-plane link (no-op where `ip` is missing).
links_up() {
  command -v ip >/dev/null 2>&1 || { log "no ip tool, leaving link state to containerlab"; return 0; }
  for i in $(data_ifs); do ip link set dev "$i" up || log "WARNING: cannot bring up $i"; done
}

# ---- L2 helpers (M2) ---------------------------------------------------------

# br_netfilter is loaded on the WSL host and defaults to 1 in every netns, which
# would push bridged frames through this node's iptables/nftables inet hooks.
# Switching must stay pure L2, so turn it off here (per-netns sysctls).
disable_br_netfilter() {
  for f in /proc/sys/net/bridge/bridge-nf-call-iptables            /proc/sys/net/bridge/bridge-nf-call-ip6tables            /proc/sys/net/bridge/bridge-nf-call-arptables; do
    [ -w "$f" ] && echo 0 > "$f"
  done
  return 0
}

# make_bridge <br>: VLAN-aware bridge with no implicit VLAN 1, no kernel STP
# (RSTP arrives in M5) and multicast flooded like a plain switch.
make_bridge() {
  run ip link add "$1" type bridge vlan_filtering 1 vlan_default_pvid 0 stp_state 0 mcast_snooping 0
  run ip link set "$1" up
}

# trunk_port <br> <if> <vid...>: 802.1Q trunk, native VLAN untagged, the rest tagged.
trunk_port() {
  local br="$1" ifc="$2" v; shift 2
  run ip link set "$ifc" master "$br"
  for v in "$@"; do
    if [ "$v" = "$NATIVE_VLAN" ]; then run bridge vlan add dev "$ifc" vid "$v" pvid untagged
    else run bridge vlan add dev "$ifc" vid "$v"; fi
  done
}

# access_port <br> <if> <vid>: untagged member of one VLAN.
access_port() {
  run ip link set "$2" master "$1"
  run bridge vlan add dev "$2" vid "$3" pvid untagged
}

# svi <br> <vid> <ip/len>: L3 interface vlan<vid> on the bridge.
svi() {
  run bridge vlan add dev "$1" vid "$2" self
  run ip link add link "$1" name "vlan$2" type vlan id "$2"
  run ip addr add "$3" dev "vlan$2"
  run ip link set "vlan$2" up
}

# config_endpoint: static address + default gateway on eth1 from host_addr.
# Replacing the default route moves it off containerlab's eth0 management net.
config_endpoint() {
  set -- $(host_addr "$NODE")
  if [ -z "${1:-}" ]; then log "no address planned for $NODE"; return 0; fi
  run ip addr add "$1" dev eth1
  run ip route replace default via "$2" dev eth1
  log "eth1 $1, default gateway $2"
}

# Hand PID 1 over to a process that never exits.
# /tmp/lab-ready tells the host scripts (wait_lab_ready) this node is configured.
keep_alive() {
  touch /tmp/lab-ready
  log "init done"
  exec tail -f /dev/null
}
