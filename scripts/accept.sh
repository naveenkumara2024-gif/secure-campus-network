#!/usr/bin/env bash
# scripts/accept.sh - per-milestone acceptance tests (CLAUDE.md section 5).
#
#   scripts/accept.sh M2      one milestone       (make accept M=M2)
#   scripts/accept.sh all     every milestone built so far
#
# Prints PASS / FAIL per check, exits non-zero if any check FAILs.
# Addresses come from nodes/common/addressing.sh, never typed here.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
cd "$REPO_ROOT"

# ping_ok <node> <ip>: true if any of 3 echo requests is answered.
ping_ok() { dx "$1" ping -c 3 -W 2 "$2" >/dev/null 2>&1; }

check() {   # check <id> <description> <command...>
  local id="$1" desc="$2"; shift 2
  if "$@"; then result "$id" PASS "$desc"; else result "$id" FAIL "$desc"; fi
}

# vlans_on <node> <if>: "<vid>[:pvid-untagged] ..." as configured on a bridge port.
vlans_on() {
  dx "$1" bridge -j vlan show dev "$2" 2>/dev/null |
    jq -r '.[0].vlans[] | "\(.vlan)" + (if ((.flags // []) | index("PVID")) and ((.flags // []) | index("Egress Untagged")) then ":native" else "" end)' |
    sort -n | tr '\n' ' ' | sed 's/ $//'
}
expected_trunk() {   # expected_trunk <vid...>: same format as vlans_on
  local v out=""
  for v in "$@"; do
    if [ "$v" = "$NATIVE_VLAN" ]; then out="$out $v:native"; else out="$out $v"; fi
  done
  echo $out | tr ' ' '\n' | sort -n | tr '\n' ' ' | sed 's/ $//'
}

# ---- M2: L2 fabric + VLANs ---------------------------------------------------
accept_M2() {
  local n ip v c ok sw dl want got

  # Same VLAN, same access switch (CLAUDE.md 5.2).
  check M2.1 "pc-student -> attacker $(host_ip attacker) (VLAN 20, both on acc1)" \
    ping_ok pc-student "$(host_ip attacker)"

  # Every PC/server reaches BOTH core SVIs of its VLAN: proves access ports,
  # the pruned uplink trunks and the inter-core trunk all carry the VLAN.
  for n in $CAMPUS_HOSTS $SERVER_HOSTS; do
    ip=$(host_ip "$n"); v=$(echo "$ip" | cut -d. -f3); ok=0
    for c in core1 core2; do ping_ok "$n" "$(core_svi_ip "$v" "$c")" || ok=1; done
    check M2.2 "$n (VLAN $v) -> core1 $(core_svi_ip "$v" core1) and core2 $(core_svi_ip "$v" core2)" [ "$ok" -eq 0 ]
  done

  # Access-switch management SVIs on the native VLAN reach both cores.
  for sw in acc1 acc2 acc3 srv-sw; do
    ok=0
    for c in core1 core2; do ping_ok "$sw" "$(core_svi_ip "$NATIVE_VLAN" "$c")" || ok=1; done
    check M2.3 "$sw mgmt $(access_mgmt_ip "$sw") (native VLAN $NATIVE_VLAN) -> both core SVIs" [ "$ok" -eq 0 ]
  done

  # Inter-core L3 link SVI over the trunk.
  check M2.4 "core1 $(core_link_ip core1) -> core2 $(core_link_ip core2) (VLAN $CORE_LINK_VLAN /30)" \
    ping_ok core1 "$(core_link_ip core2)"

  # Trunks carry exactly the pruned VLAN list, native VLAN untagged, both ends agree.
  for dl in $CORE_DOWNLINKS; do
    sw="${dl#*:}"; want=$(expected_trunk $(trunk_vlans "$sw"))
    got="$(vlans_on "$sw" eth-up1) | $(vlans_on core1 "${dl%%:*}") | $(vlans_on core2 "${dl%%:*}")"
    check M2.5 "$sw trunks carry [$want] on $sw eth-up1, core1 and core2 ${dl%%:*}" \
      [ "$got" = "$want | $want | $want" ]
  done

  # VLAN isolation: a frame from VLAN 20 must never reach VLAN 30's broadcast domain.
  # pc-student borrows an address in 10.10.30.0/24 on its VLAN 20 port for one
  # ping; if VLANs leak, core SVIs in VLAN 30 would answer.
  dx pc-student ip addr add 10.10.30.250/24 dev eth1 2>/dev/null
  if dx pc-student ping -c 2 -W 1 -I 10.10.30.250 "$(core_svi_ip 30 core1)" >/dev/null 2>&1; then ok=1; else ok=0; fi
  dx pc-student ip addr del 10.10.30.250/24 dev eth1 2>/dev/null
  check M2.6 "VLAN isolation: VLAN 20 port cannot reach VLAN 30 SVI at L2" [ "$ok" -eq 0 ]
}

MILESTONES="M2"
want="${1:-all}"
[ "$want" = all ] && want="$MILESTONES"
wait_lab_ready 60 || true
printf '%s== acceptance: %s ==%s\n' "$C_C" "$want" "$C_0"
for m in $want; do
  if declare -F "accept_$m" >/dev/null; then "accept_$m"
  else result "$m" SKIP "no acceptance test for $m (built: $MILESTONES)"; fi
done
printf '%s== %d PASS, %d FAIL ==%s\n' "$C_C" "$PASS_N" "$FAIL_N" "$C_0"
[ "$FAIL_N" -eq 0 ]
