#!/bin/sh
# nodes/access/init.sh - ACC-SW1/2/3 and SRV-SW: L2 access switch (M2 bridge+VLANs, M5 RSTP, M6/M7 Guardian)
#
# M1 (topology skeleton): wait for containerlab to plug in this node's links,
# bring them up and stay alive. Later milestones extend this file.
. /lab/common/node-lib.sh

wait_for_links
links_up
keep_alive
