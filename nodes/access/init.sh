#!/bin/sh
# nodes/access/init.sh - ACC-SW1/2/3 and SRV-SW: L2 access switch.
#
# M2: one VLAN-aware bridge br0. Access ports are untagged members of their VLAN,
#     both uplinks are pruned 802.1Q trunks (native VLAN 99 untagged), and a
#     management SVI sits on VLAN 99.
# Later: M5 RSTP (mstpd) on br0, M6/M7 Campus Guardian on the access ports.
. /lab/common/node-lib.sh

wait_for_links
links_up
disable_br_netfilter

make_bridge br0
vlans=$(trunk_vlans "$NODE")
for up in eth-up1 eth-up2; do
  trunk_port br0 "$up" $vlans
done
# M2 has no spanning tree yet, and every access switch is dual-homed to two cores
# that are trunked together: keep the core2 uplink down so there is no L2 loop.
# M5 removes this and lets RSTP block the redundant path instead.
run ip link set eth-up2 down

for pv in $(access_ports "$NODE"); do
  access_port br0 "${pv%%:*}" "${pv#*:}"
done

svi br0 "$NATIVE_VLAN" "$(access_mgmt_ip "$NODE")/24"
# Management traffic to the rest of the campus goes via the VLAN 99 gateway
# (the VRRP VIP from M4); eth0 keeps containerlab's own default route.
run ip route add 10.10.0.0/16 via "$(vlan_vip "$NATIVE_VLAN")"

log "br0 trunks carry VLANs $(echo $vlans); access ports $(access_ports "$NODE")"
keep_alive
