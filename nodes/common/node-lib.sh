#!/bin/sh
# nodes/common/node-lib.sh - helpers sourced by every node's init.sh.
#
# POSIX sh only: it runs under busybox ash (Alpine images) and dash/bash (Debian/Ubuntu).
#
# IMPORTANT: an init.sh must never exit non-zero. Containerlab gives linux nodes an
# on-failure restart policy, and a restarted container loses every lab link except eth0.
# So: no `set -e`, log problems, and always finish with keep_alive.

NODE="$(hostname)"

log() { echo "[$NODE] $(date +%H:%M:%S) $*"; }

# Data-plane interfaces: every Ethernet-type link except lo, the eth0 management
# port, kernel fallback tunnel devices, VLAN sub-interfaces and the bridges/bonds
# that init scripts create themselves.
data_ifs() {
  for d in /sys/class/net/*; do
    n="${d##*/}"
    case "$n" in lo|eth0|gretap0|erspan0|ip6gre0|*.*) continue ;; esac
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

# Hand PID 1 over to a process that never exits.
keep_alive() {
  log "init done"
  exec tail -f /dev/null
}
