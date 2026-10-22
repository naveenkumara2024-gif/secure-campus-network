#!/usr/bin/env bash
# scripts/lib.sh - shared bash helpers (colour, assert, node exec, counter read).
# Sourced by scripts/verify.sh and Makefile targets; run from WSL2 Ubuntu.

LAB="${LAB:-campus}"
TOPO="${TOPO:-campus.clab.yml}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The lab address plan (same file the nodes source).
. "$REPO_ROOT/nodes/common/addressing.sh"

# sudo only when not already root; plain docker when the user is in the docker group.
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
if docker info >/dev/null 2>&1; then DOCKER="docker"; else DOCKER="$SUDO docker"; fi

if [ -t 1 ]; then
  C_G=$'\033[1;32m'; C_R=$'\033[1;31m'; C_Y=$'\033[1;33m'; C_C=$'\033[1;36m'; C_0=$'\033[0m'
else
  C_G=""; C_R=""; C_Y=""; C_C=""; C_0=""
fi

info() { printf '%s[info]%s %s\n' "$C_C" "$C_0" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$C_Y" "$C_0" "$*"; }

# Container name of a topology node, and `docker exec` into it.
cname() { echo "clab-$LAB-$1"; }
dx()    { local n="$1"; shift; $DOCKER exec "$(cname "$n")" "$@"; }

# Node names: the 4-space-indented keys under `topology.nodes` in the topology file.
topo_nodes() {
  awk '/^  nodes:/{f=1; next} /^  links:/{f=0}
       f && /^    [A-Za-z0-9_-]+:[[:space:]]*$/ {gsub(/[ :]/, ""); print}' "$REPO_ROOT/$TOPO"
}

# Number of lab links a node has in the topology (endpoint occurrences).
topo_link_count() {
  grep -E '^[[:space:]]*- endpoints:' "$REPO_ROOT/$TOPO" | grep -o "\"$1:" | wc -l | tr -d ' '
}

node_running() { [ "$($DOCKER inspect -f '{{.State.Running}}' "$(cname "$1")" 2>/dev/null)" = "true" ]; }

lab_all_running() {
  local n
  for n in $(topo_nodes); do node_running "$n" || return 1; done
  return 0
}

# Data-plane links a running node can see (same rule its init.sh uses).
node_link_count() { dx "$1" sh -c '. /lab/common/node-lib.sh; data_ifs | wc -l' 2>/dev/null | tr -d ' \r'; }

# Healthy lab = every node running AND every node still has all its topology links.
# (A container restarted by Docker on its own is running but has lost its links.)
lab_healthy() {
  local n
  for n in $(topo_nodes); do
    node_running "$n" || return 1
    [ "$(node_link_count "$n")" -ge "$(topo_link_count "$n")" ] || return 1
  done
  return 0
}

# Block until every node's init.sh has finished (it touches /tmp/lab-ready),
# so `make up && make verify` never tests a half-configured lab.
wait_lab_ready() {
  local n t=0 pending
  while :; do
    pending=""
    for n in $(topo_nodes); do
      dx "$n" test -f /tmp/lab-ready 2>/dev/null || pending="$pending $n"
    done
    [ -z "$pending" ] && return 0
    if [ "$t" -ge "${1:-90}" ]; then warn "not ready after ${t}s:$pending"; return 1; fi
    sleep 2; t=$((t + 2))
  done
}

# ---- acceptance-table output -------------------------------------------------
PASS_N=0; FAIL_N=0; SKIP_N=0
result() {   # result <ID> <PASS|FAIL|SKIP> <detail...>
  local id="$1" st="$2" c=""; shift 2
  case "$st" in
    PASS) c="$C_G"; PASS_N=$((PASS_N + 1)) ;;
    FAIL) c="$C_R"; FAIL_N=$((FAIL_N + 1)) ;;
    *)    c="$C_Y"; SKIP_N=$((SKIP_N + 1)) ;;
  esac
  printf '%-4s %s%-4s%s  %s\n' "$id" "$c" "$st" "$C_0" "$*"
}

# assert <ID> <description> <command...>: PASS if the command succeeds.
assert() {
  local id="$1" desc="$2"; shift 2
  if "$@" >/dev/null 2>&1; then result "$id" PASS "$desc"; else result "$id" FAIL "$desc"; fi
}

# dx_has <node> <pattern> <command...>: the command's output (inside the node)
# contains the pattern. Output is captured first: piping into `grep -q` would
# kill the command early (SIGPIPE) and fail the pipeline under `pipefail`.
dx_has() {
  local n="$1" pat="$2" out; shift 2
  out=$(dx "$n" "$@" 2>/dev/null)
  grep -q -- "$pat" <<<"$out"
}

# check <ID> <description> <command...>: PASS if the command succeeds (output kept).
check() {
  local id="$1" desc="$2"; shift 2
  if "$@"; then result "$id" PASS "$desc"; else result "$id" FAIL "$desc"; fi
}

# retry <seconds> <command...>: re-run once a second until it succeeds.
retry() {
  local t="$1" i=0; shift
  until "$@"; do i=$((i + 1)); [ "$i" -ge "$t" ] && return 1; sleep 1; done
}

# ---- probes run inside lab nodes -------------------------------------------------
ping_ok()      { dx "$1" ping -c 3 -W 2 "$2" >/dev/null 2>&1; }     # any reply
ping_blocked() { ! dx "$1" ping -c 2 -W 1 "$2" >/dev/null 2>&1; }   # no reply at all

# curl_rc <node> <url>: curl exit code. 0 = success, 7 = connection refused (the
# packet reached the server), 28 = timeout (a firewall dropped it silently).
curl_rc()   { dx "$1" curl -s -m 3 -o /dev/null "$2" >/dev/null 2>&1; echo $?; }
http_code() { dx "$1" curl -s -m 3 -o /dev/null -w '%{http_code}' "$2" 2>/dev/null; }

# nft_counter <node> <family> <table> <counter>: packets seen by a named counter.
nft_counter() {
  dx "$1" nft list counter "$2" "$3" "$4" 2>/dev/null |
    awk '{for (i = 1; i < NF; i++) if ($i == "packets") {print $(i + 1); exit}}'
}
# Campus Guardian counter (M6+): guardian_counter <node> <counter>
guardian_counter() { nft_counter "$1" netdev guardian "$2"; }

# Continuous ping inside a node (one echo every 0.2 s, at most 60 s), for failover tests.
# bg_ping_start <node> <ip> <tag>  ...  bg_ping_lost <node> <tag> -> "<lost> <received>"
# Lost = sequence numbers with no echo reply between the first and the last reply.
# (-c, not -w: iputils ping -w quits at the first ICMP error.)
bg_ping_start() {
  $DOCKER exec -d "$(cname "$1")" sh -c "ping -i 0.2 -c 300 $2 > /tmp/ping-$3.log 2>&1"
}
bg_ping_lost() {
  dx "$1" sh -c "pkill -INT -x ping; sleep 0.5; cat /tmp/ping-$2.log" 2>/dev/null |
    grep 'bytes from' | grep -oE 'icmp_seq=[0-9]+' | cut -d= -f2 |
    awk 'NR == 1 {p = $1; n = 1; next} {if ($1 > p + 1) l += $1 - p - 1; p = $1; n++} END {print l + 0, n + 0}'
}

# vip_holders <vid>: which cores currently hold that VLAN's gateway VIP.
vip_holders() {
  local v="$1" n out=""
  for n in core1 core2; do
    dx_has "$n" " $(vlan_vip "$v")/24" ip -4 addr show dev "vlan$v" && out="$out $n"
  done
  echo $out
}

# OSPF adjacency plan: which router IDs each router must see as neighbours.
ospf_peers() {
  case "$1" in
    core1) echo "$(router_id core2) $(router_id edge1)" ;;
    core2) echo "$(router_id core1) $(router_id edge2)" ;;
    edge1) router_id core1 ;;
    edge2) router_id core2 ;;
  esac
}
# ospf_full <node> <router-id...>: FRR reports every listed neighbour as Full.
ospf_full() {
  local n="$1" rid json; shift
  json=$(dx "$n" vtysh -c "show ip ospf neighbor json" 2>/dev/null) || return 1
  for rid in "$@"; do
    [ "$(jq -r --arg r "$rid" '.neighbors[$r][0].converged // empty' <<<"$json")" = Full ] || return 1
  done
}
