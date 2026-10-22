#!/bin/sh
# nodes/edge/init.sh - EDGE-R1/2: WAN edge (M3 FRR OSPF, NAT, M8 strongSwan PQ-IPsec)
#
# M1 (topology skeleton): wait for containerlab to plug in this node's links,
# bring them up and stay alive. Later milestones extend this file.
. /lab/common/node-lib.sh

wait_for_links
links_up
keep_alive
