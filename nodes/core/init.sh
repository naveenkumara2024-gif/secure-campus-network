#!/bin/sh
# nodes/core/init.sh - CORE-SW1/2: collapsed-core multilayer switch.
#
# M2: one VLAN-aware bridge br0 with
#     - pruned trunks to each access switch (eth-acc1..3, eth-srv),
#     - the inter-core trunk carrying every campus VLAN plus VLAN 200,
#     - an SVI per campus VLAN (.2 on the VLAN's master core, .3 on the backup)
#       and the 10.10.200.0/30 inter-core L3 link on SVI vlan200.
# Later: M3 FRR OSPF + inter-VLAN nft policy, M4 keepalived VRRP, M5 LACP bond.
. /lab/common/node-lib.sh

wait_for_links
links_up
disable_br_netfilter

make_bridge br0
for dl in $CORE_DOWNLINKS; do
  trunk_port br0 "${dl%%:*}" $(trunk_vlans "${dl#*:}")
done
# Inter-core trunk. M2 uses eth-peer1 only; M5 bonds eth-peer1 + eth-peer2 (LACP)
# and puts the bond here instead. Until then eth-peer2 stays down (no loop).
trunk_port br0 eth-peer1 $(vlan_ids) "$CORE_LINK_VLAN"
run ip link set eth-peer2 down

for v in $(vlan_ids); do
  svi br0 "$v" "$(core_svi_ip "$v" "$NODE")/24"
done
svi br0 "$CORE_LINK_VLAN" "$(core_link_ip "$NODE")/30"

log "SVIs: $(for v in $(vlan_ids); do printf 'vlan%s=%s ' "$v" "$(core_svi_ip "$v" "$NODE")"; done)vlan$CORE_LINK_VLAN=$(core_link_ip "$NODE")"
keep_alive
