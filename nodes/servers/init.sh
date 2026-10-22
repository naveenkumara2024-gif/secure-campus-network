#!/bin/sh
# nodes/servers/init.sh - server farm, VLAN 40: dhcp, dns, radius, syslog, ntp, web.
#
# M2: static service IP (CLAUDE.md section 3) and default gateway 10.10.40.1.
# M3: web runs nginx (target of the student -> web policy test).
# Later: M9 starts the other services (Kea, unbound, FreeRADIUS, rsyslog, chrony).
. /lab/common/node-lib.sh

wait_for_links
links_up
config_endpoint

case "$NODE" in
  web)
    echo "<h1>Campus web server</h1><p>$(host_ip web) on VLAN 40 (SERVER-FARM)</p>" \
      > /usr/share/nginx/html/index.html
    run nginx
    ;;
esac

keep_alive
