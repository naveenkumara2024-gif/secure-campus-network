#!/bin/sh
# nodes/isp/init.sh - ISP1/2: upstream providers and the "internet" between them.
#
# M3: customer link to its edge, a transit link to the other ISP, and the
#     internet host INTERNET_HOST on loopback (same address on both ISPs, so the
#     campus reaches it through whichever edge it exits). ISPs know nothing about
#     the private campus or branch subnets: the edges must NAT (or tunnel) to them.
. /lab/common/node-lib.sh

wait_for_links
links_up
drop_mgmt_default

run ip addr add "$(p2p_addr "$NODE" eth-edge)" dev eth-edge
run ip addr add "$(p2p_addr "$NODE" eth-transit)" dev eth-transit
run ip addr add "$INTERNET_HOST/32" dev lo

# The other ISP's customer (edge public /30) is reached across the transit link.
peer=$(other_isp "$NODE")
run ip route add "$(net_of "$(p2p_addr "$peer" eth-edge)")" via "$(addr_ip "$(p2p_addr "$peer" eth-transit)")"

log "customer $(p2p_addr "$NODE" eth-edge), transit $(p2p_addr "$NODE" eth-transit), internet host $INTERNET_HOST"
keep_alive
