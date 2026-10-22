#!/bin/sh
# nodes/core/init.sh - CORE-SW1/2: collapsed-core multilayer switch.
#
# M2: VLAN-aware bridge br0, pruned trunks to the access switches, inter-core trunk.
# M3: SVIs + routing. On each VLAN the VRRP master core has SVI .2/24 and the
#     backup core has SVI .3/32 only, so the VLAN is always delivered by the core
#     holding its gateway (NOTES.md 26).
#     FRR runs OSPF area 0 on the inter-core and core-edge /30s and redistributes
#     the VLAN /24s. intervlan.nft enforces the least-privilege policy.
# M4: keepalived VRRPv3 owns each VLAN's gateway VIP .1.
# Later: M5 LACP bond + RSTP.
. /lab/common/node-lib.sh

wait_for_links
links_up
disable_br_netfilter
drop_mgmt_default

# ---- L2 (M2) ----------------------------------------------------------------
make_bridge br0
for dl in $CORE_DOWNLINKS; do
  trunk_port br0 "${dl%%:*}" $(trunk_vlans "${dl#*:}")
done
# Inter-core trunk. Until M5 bonds eth-peer1 + eth-peer2 (LACP), only eth-peer1
# is used and eth-peer2 stays down so there is no L2 loop.
trunk_port br0 eth-peer1 $(vlan_ids) "$CORE_LINK_VLAN"
run ip link set eth-peer2 down

# ---- SVIs (M3) --------------------------------------------------------------
for v in $(vlan_ids); do
  ip=$(core_svi_ip "$v" "$NODE")
  if [ "$(vlan_master "$v")" = "$NODE" ]; then
    svi br0 "$v" "$ip/24"
  else
    svi br0 "$v" "$ip/32"
    # Replies sourced from this /32 SVI still leave straight through it.
    run ip route add "$(vlan_subnet "$v")" dev "vlan$v" table $((1000 + v))
    run ip rule add from "$ip" lookup $((1000 + v)) priority 100
  fi
done
svi br0 "$CORE_LINK_VLAN" "$(core_link_ip "$NODE")/30"
run ip addr add "$(p2p_addr "$NODE" eth-edge)" dev eth-edge

# ---- Routing: FRR OSPF (M3) -------------------------------------------------
render /lab/node/frr.conf.tmpl /etc/frr/frr.conf \
  NODE="$NODE" ROUTER_ID="$(router_id "$NODE")" CAMPUS_NET="$CAMPUS_NET" \
  CORE_LINK_VLAN="$CORE_LINK_VLAN" \
  CORE_LINK_NET="$(net_of "$(core_link_ip "$NODE")/30")" \
  EDGE_LINK_NET="$(net_of "$(p2p_addr "$NODE" eth-edge)")"
start_frr /lab/node/daemons

# ---- Inter-VLAN policy (M3) -------------------------------------------------
nft_defines > /run/campus-defines.nft
run nft -f /lab/node/intervlan.nft

# ---- Gateway HA: keepalived VRRPv3 (M4) --------------------------------------
# One instance per VLAN, VRID = VLAN id, priority 110 on the VLAN's master core and
# 100 on the backup, preempt on. keepalived owns the VIP .1/24: when it moves, the
# connected /24 (and its OSPF advertisement) moves with it (NOTES.md 26).
mkdir -p /etc/keepalived
kconf=/etc/keepalived/keepalived.conf
tmpl=/lab/node/keepalived.conf.tmpl
sed '/^#### INSTANCE ####$/,$d' "$tmpl" > /tmp/ka-head.tmpl
sed '1,/^#### INSTANCE ####$/d' "$tmpl" > /tmp/ka-inst.tmpl
render /tmp/ka-head.tmpl "$kconf" NODE="$NODE"
for v in $(vlan_ids); do
  if [ "$(vlan_master "$v")" = "$NODE" ]; then prio=110; else prio=100; fi
  render /tmp/ka-inst.tmpl /tmp/ka-one.conf VID="$v" VNAME="$(vlan_name "$v")" \
    MASTER="$(vlan_master "$v")" PRIO="$prio" ADVERT="$VRRP_ADVERT" VIP="$(vlan_vip "$v")"
  cat /tmp/ka-one.conf >> "$kconf"
done
# Foreground (-n) in the background, logging to a file: there is no syslog yet (M9).
sh /lab/node/keepalived-ctl.sh start >/dev/null
log "keepalived started ($(vlan_ids | wc -l) VRRP instances, advert ${VRRP_ADVERT}s)"

log "masters here: $(for v in $(vlan_ids); do [ "$(vlan_master "$v")" = "$NODE" ] && printf '%s ' "$v"; done)| OSPF router-id $(router_id "$NODE")"
keep_alive
