#!/bin/sh
# nodes/servers/init.sh - Server farm, VLAN 40: dhcp, dns, radius, syslog, ntp, web (services arrive in M9)
#
# M1 (topology skeleton): wait for containerlab to plug in this node's links,
# bring them up and stay alive. Later milestones extend this file.
. /lab/common/node-lib.sh

wait_for_links
links_up
keep_alive
