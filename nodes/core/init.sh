#!/bin/sh
# nodes/core/init.sh - CORE-SW1/2: multilayer switch (M2 bridges+SVIs, M3 FRR+nft, M4 keepalived, M5 LACP bond)
#
# M1 (topology skeleton): wait for containerlab to plug in this node's links,
# bring them up and stay alive. Later milestones extend this file.
. /lab/common/node-lib.sh

wait_for_links
links_up
keep_alive
