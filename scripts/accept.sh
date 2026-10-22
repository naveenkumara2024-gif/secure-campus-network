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

# (ping_ok, ping_blocked, check, nft_counter, ospf_full ... live in scripts/lib.sh)

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

# ---- M3: core routing, inter-VLAN routing, least-privilege policy -----------------
has_route() { dx_has "$1" "$3" ip route show "$2"; }   # <node> <prefix> <pattern>
ospf_vlan_routes() { dx "$1" ip route show proto ospf 2>/dev/null | grep -cE '^10\.10\.[0-9]+\.0/24 '; }
edge_of() { echo "edge${1#core}"; }                                       # core1 -> edge1
hops_to() { dx "$1" traceroute -I -n -w 1 -q 1 -m 6 "$2" 2>/dev/null | awk 'NR > 1 {print $2}' | tr '\n' ' ' | sed 's/ $//'; }

accept_M3() {
  local n c other v ok b a r gm sm hops want

  # M3.1 OSPF: each core is Full with the other core and its edge (CLAUDE.md 5.3).
  for n in core1 core2 edge1 edge2; do
    check M3.1 "$n OSPF Full with $(ospf_peers "$n" | sed 's/ /, /g')" retry 30 ospf_full "$n" $(ospf_peers "$n")
  done

  # M3.2 Routing tables. A VLAN is reached through its VRRP master core (backup SVIs
  # are /32), each core's default comes from its own edge, edges know every VLAN.
  for c in core1 core2; do
    other=core2; [ "$c" = core2 ] && other=core1
    ok=0
    for v in $(vlan_ids); do
      [ "$(vlan_master "$v")" = "$c" ] && continue
      has_route "$c" "$(vlan_subnet "$v")" "via $(core_link_ip "$other") dev vlan$CORE_LINK_VLAN proto ospf" || ok=1
    done
    check M3.2 "$c reaches the VLANs that $other masters via OSPF over vlan$CORE_LINK_VLAN" [ "$ok" -eq 0 ]
    check M3.2 "$c default route learned by OSPF from $(edge_of "$c")" \
      has_route "$c" default "via $(addr_ip "$(p2p_addr "$(edge_of "$c")" eth-core)") .*proto ospf"
  done
  for n in edge1 edge2; do
    check M3.2 "$n learned all $(vlan_ids | wc -l) campus VLAN /24s by OSPF" \
      [ "$(ospf_vlan_routes "$n")" -eq "$(vlan_ids | wc -l)" ]
  done

  # M3.3 Inter-VLAN routing (V3), and the path proves the design: VLAN 20's master
  # (core1) hands the flow to VLAN 30's master (core2), which delivers it.
  check M3.3 "VLAN 20 -> VLAN 30: pc-student -> pc-library $(host_ip pc-library)" ping_ok pc-student "$(host_ip pc-library)"
  check M3.3 "VLAN 30 -> VLAN 20: pc-library -> pc-student $(host_ip pc-student)" ping_ok pc-library "$(host_ip pc-student)"
  hops=$(hops_to pc-student "$(host_ip pc-library)")
  want="$(core_svi_ip 20 core1) $(core_link_ip core2) $(host_ip pc-library)"
  check M3.3 "path student -> library is core1, core2, host [$hops]" [ "$hops" = "$want" ]

  # M3.4 Least-privilege policy (V4). Every block must also show up on a counter.
  gm=$(vlan_master 60)
  b=$(nft_counter "$gm" inet intervlan guest_isolation)
  ping_blocked pc-guest "$(host_ip dhcp)"; r=$?
  ping_blocked pc-guest "$(host_ip pc-student)"; r=$((r + $?))
  a=$(nft_counter "$gm" inet intervlan guest_isolation)
  check M3.4 "guest -> server farm $(host_ip dhcp) and -> pc-student: both blocked" [ "$r" -eq 0 ]
  check M3.4 "$gm guest_isolation counter rose ($b -> $a)" [ "${a:-0}" -gt "${b:-0}" ]
  check M3.4 "student -> web http://$(host_ip web)/ returns 200" [ "$(http_code pc-student "http://$(host_ip web)/")" = 200 ]
  check M3.4 "student -> web port 8080 silently dropped (curl timeout)" [ "$(curl_rc pc-student "http://$(host_ip web):8080/")" = 28 ]
  check M3.4 "faculty -> web port 8080 allowed (reaches the server: refused)" [ "$(curl_rc pc-faculty "http://$(host_ip web):8080/")" = 7 ]
  sm=$(vlan_master 20)
  b=$(nft_counter "$sm" inet intervlan policy_deny)
  ping_blocked pc-student "$(host_ip dhcp)"; r=$?
  ping_blocked phone "$(host_ip pc-student)"; r=$((r + $?))
  a=$(nft_counter "$sm" inet intervlan policy_deny)
  check M3.4 "student -> dhcp server and voice -> student blocked; $sm policy_deny rose ($b -> $a)" \
    [ "$r" -eq 0 -a "${a:-0}" -gt "${b:-0}" ]

  # M3.5 Internet through the edges' PAT; each VLAN exits via its master core's edge.
  for n in pc-student pc-guest; do
    v=$(host_ip "$n" | cut -d. -f3); c=$(vlan_master "$v"); c=$(edge_of "$c")
    b=$(nft_counter "$c" ip campus_nat nat_out)
    ping_ok "$n" "$INTERNET_HOST"; r=$?
    a=$(nft_counter "$c" ip campus_nat nat_out)
    check M3.5 "$n -> internet host $INTERNET_HOST through $c PAT (nat_out $b -> $a)" [ "$r" -eq 0 -a "${a:-0}" -gt "${b:-0}" ]
  done
  check M3.5 "lab is sealed: pc-student cannot reach the real internet (1.1.1.1)" ping_blocked pc-student 1.1.1.1

  # M3.6 Outside ACL: an internet host tries to open a connection into the campus.
  # isp1 gets a route to the campus for one ping; edge1 must drop and count it.
  dx isp1 ip route add "$CAMPUS_NET" via "$(addr_ip "$(p2p_addr edge1 eth-isp)")" 2>/dev/null
  b=$(nft_counter edge1 inet perimeter inbound_drop)
  ping_blocked isp1 "$(host_ip pc-student)"; r=$?
  a=$(nft_counter edge1 inet perimeter inbound_drop)
  dx isp1 ip route del "$CAMPUS_NET" 2>/dev/null
  check M3.6 "internet -> campus (isp1 -> pc-student) dropped by edge1 outside ACL ($b -> $a)" \
    [ "$r" -eq 0 -a "${a:-0}" -gt "${b:-0}" ]
}

# ---- M4: gateway HA with VRRPv3 (keepalived) --------------------------------------
# A whole-core outage (V5) needs the second uplinks, which RSTP enables in M5. Here
# the VRRP mechanism is tested on its own: core1 hands its gateways over and back.
gateway_ok() { dx_has "$1" "via $2" ip route show default && ping_ok "$1" "$2"; }   # <node> <gw>
vrrp_heard() {   # vrrp_heard <listener> <vrid> <sender-ip> <prio>
  dx_has "$1" "$3 > 224.0.0.18: VRRPv3, Advertisement, vrid $2, prio $4"     timeout 3 tcpdump -nnli "vlan$2" -c 2 vrrp
}

accept_M4() {
  local v n gw lost rcv l2 r2 c1vlans ok

  # M4.1 Every VLAN's VIP is held by its planned master, and only by it.
  for v in $(vlan_ids); do
    check M4.1 "VLAN $v gateway $(vlan_vip "$v") held by $(vlan_master "$v") only" \
      [ "$(vip_holders "$v")" = "$(vlan_master "$v")" ]
  done

  # M4.2 Every PC and server uses its VLAN's VIP as default gateway, and it answers.
  for n in $CAMPUS_HOSTS $SERVER_HOSTS; do
    set -- $(host_addr "$n"); gw="$2"
    check M4.2 "$n default gateway $gw (VIP) answers" gateway_ok "$n" "$gw"
  done

  # M4.3 Real VRRPv3 adverts on the wire: the backup core hears the master's.
  check M4.3 "core2 hears VRRPv3 adverts for VRID 20 from core1 $(core_svi_ip 20 core1), prio 110" \
    vrrp_heard core2 20 "$(core_svi_ip 20 core1)" 110

  # M4.4 Failover: core1 stops VRRP while pc-student pings its gateway and a PC in
  # another VLAN. Every core1 VIP must move to core2 and both pings keep going.
  c1vlans=$(for v in $(vlan_ids); do [ "$(vlan_master "$v")" = core1 ] && echo "$v"; done)
  bg_ping_start pc-student "$(vlan_vip 20)" gw
  bg_ping_start pc-student "$(host_ip pc-library)" routed
  sleep 2
  dx core1 sh /lab/node/keepalived-ctl.sh stop >/dev/null
  sleep 2
  ok=0; for v in $c1vlans; do [ "$(vip_holders "$v")" = core2 ] || ok=1; done
  check M4.4 "core1 VRRP down: VIPs of VLANs $(echo $c1vlans) moved to core2" [ "$ok" -eq 0 ]

  # M4.5 Preempt: core1 comes back with priority 110 and takes its gateways back.
  dx core1 sh /lab/node/keepalived-ctl.sh start >/dev/null
  sleep 3
  ok=0; for v in $c1vlans; do [ "$(vip_holders "$v")" = core1 ] || ok=1; done
  check M4.5 "core1 VRRP back: preempt returned VLANs $(echo $c1vlans) to core1" [ "$ok" -eq 0 ]
  sleep 1
  read -r lost rcv <<<"$(bg_ping_lost pc-student gw)"
  read -r l2 r2 <<<"$(bg_ping_lost pc-student routed)"
  check M4.5 "gateway ping through failover and preempt: $lost lost, $rcv received (limit 2)" \
    [ "$rcv" -gt 20 -a "$lost" -le 2 ]
  check M4.5 "routed ping VLAN 20 -> 30 through both: $l2 lost, $r2 received (limit 2)" \
    [ "$r2" -gt 20 -a "$l2" -le 2 ]
}

MILESTONES="M2 M3 M4"
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
