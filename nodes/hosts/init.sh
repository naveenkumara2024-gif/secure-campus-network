#!/bin/sh
# nodes/hosts/init.sh - endpoints: PCs, phone, attacker, branch host.
#
# M2: static address and default gateway on eth1 from the address plan
#     (gateway = VRRP VIP, live from M4). M7/M9 move campus PCs to DHCP.
. /lab/common/node-lib.sh

wait_for_links
links_up
config_endpoint
keep_alive
