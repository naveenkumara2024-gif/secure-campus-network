#!/bin/sh
# nodes/edge/init.sh - EDGE-R1/2: WAN edge router.
#
# M3: addresses on eth-core / eth-isp (edge2 also eth-branch), FRR OSPF towards
#     its core with a static default to its ISP (originated into OSPF), and
#     nftables perimeter filter + PAT (nat.nft).
# Later: M8 strongSwan post-quantum IPsec between edge1 and edge2.
. /lab/common/node-lib.sh

wait_for_links
links_up
drop_mgmt_default

for ifc in eth-core eth-isp eth-branch; do
  a=$(p2p_addr "$NODE" "$ifc")
  [ -n "$a" ] && run ip addr add "$a" dev "$ifc"
done

isp_gw=$(addr_ip "$(p2p_addr "$(edge_isp "$NODE")" eth-edge)")
render /lab/node/frr.conf.tmpl /etc/frr/frr.conf \
  NODE="$NODE" ROUTER_ID="$(router_id "$NODE")" \
  CORE_LINK_NET="$(net_of "$(p2p_addr "$NODE" eth-core)")" \
  ISP_GW="$isp_gw"
start_frr /lab/node/daemons

nft_defines > /run/campus-defines.nft
run nft -f /lab/node/nat.nft

log "public $(p2p_addr "$NODE" eth-isp), ISP gateway $isp_gw"
keep_alive
