#!/bin/sh
# nodes/hosts/init.sh - Endpoints: PCs, phone, attacker, branch host (addressing arrives in M2)
#
# M1 (topology skeleton): wait for containerlab to plug in this node's links,
# bring them up and stay alive. Later milestones extend this file.
. /lab/common/node-lib.sh

wait_for_links
links_up
keep_alive
