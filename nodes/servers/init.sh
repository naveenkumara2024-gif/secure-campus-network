#!/bin/sh
# nodes/servers/init.sh - server farm, VLAN 40: dhcp, dns, radius, syslog, ntp, web.
#
# M2: static service IP (CLAUDE.md section 3) and default gateway 10.10.40.1.
# Later: M9 starts each node's service (Kea, unbound, FreeRADIUS, rsyslog, chrony, nginx).
. /lab/common/node-lib.sh

wait_for_links
links_up
config_endpoint
keep_alive
