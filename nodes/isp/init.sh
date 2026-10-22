#!/bin/sh
# nodes/isp/init.sh - ISP1/2: upstream providers and the 'internet' transit between them
#
# M1 (topology skeleton): wait for containerlab to plug in this node's links,
# bring them up and stay alive. Later milestones extend this file.
. /lab/common/node-lib.sh

wait_for_links
links_up
keep_alive
