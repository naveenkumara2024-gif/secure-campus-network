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

# Campus Guardian named-counter packet value (M6+): guardian_counter <node> <counter>
guardian_counter() {
  dx "$1" nft list counter netdev guardian "$2" 2>/dev/null |
    awk '{for (i = 1; i < NF; i++) if ($i == "packets") {print $(i + 1); exit}}'
}
