#!/usr/bin/env bash
# scripts/verify.sh - acceptance matrix V1..V12 (CLAUDE.md section 6).
#
# Prints one PASS / FAIL / SKIP line per row and exits non-zero if any row FAILs.
# SKIP means the milestone that implements that row has not been built yet;
# each milestone replaces its rows' SKIP with a real check.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
cd "$REPO_ROOT"

# V1 - every node is running and has all of its topology links plugged in.
check_V1() {
  local n total=0 up=0 want have down=() unwired=()
  for n in $(topo_nodes); do
    total=$((total + 1))
    if ! node_running "$n"; then down+=("$n"); continue; fi
    up=$((up + 1))
    want=$(topo_link_count "$n"); have=$(node_link_count "$n")
    [ "${have:-0}" -ge "$want" ] || unwired+=("$n(${have:-0}/$want)")
  done
  if [ "$total" -eq 0 ]; then
    result V1 FAIL "no nodes found in $TOPO"
  elif [ "${#down[@]}" -gt 0 ]; then
    result V1 FAIL "$up/$total running; not running: ${down[*]}"
  elif [ "${#unwired[@]}" -gt 0 ]; then
    result V1 FAIL "all $total running but links missing: ${unwired[*]}"
  else
    result V1 PASS "all $total nodes running, every topology link present"
  fi
}

# Rows not implemented yet -> milestone that will implement them.
declare -A PENDING=(
  [V2]="M3 OSPF"            [V3]="M3 inter-VLAN routing" [V4]="M3 inter-VLAN policy"
  [V5]="M4 VRRP failover"   [V6]="M5 RSTP/LACP"          [V7]="M6 Guardian loads"
  [V8]="M10 Guardian drops" [V9]="M10 bystander safe"    [V10]="M10 quarantine"
  [V11]="M8 PQ-IPsec"       [V12]="M9 services"
)

wait_lab_ready 60 || true
printf '%s== campus lab acceptance matrix ==%s\n' "$C_C" "$C_0"
for id in V1 V2 V3 V4 V5 V6 V7 V8 V9 V10 V11 V12; do
  if declare -F "check_$id" >/dev/null; then
    "check_$id"
  else
    result "$id" SKIP "not built yet (${PENDING[$id]})"
  fi
done
printf '%s== %d PASS, %d FAIL, %d SKIP ==%s\n' "$C_C" "$PASS_N" "$FAIL_N" "$SKIP_N" "$C_0"
[ "$FAIL_N" -eq 0 ]
