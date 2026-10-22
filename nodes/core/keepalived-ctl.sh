#!/bin/sh
# nodes/core/keepalived-ctl.sh - start/stop VRRP on a core (used by init.sh, tests, demo).
#
#   keepalived-ctl.sh start   render nothing, just (re)start keepalived with the
#                             config init.sh rendered to /etc/keepalived/keepalived.conf
#   keepalived-ctl.sh stop    stop keepalived; it sends priority-0 adverts first, so
#                             the backup core takes every VIP over at once
#   keepalived-ctl.sh status  "MASTER vlanX ..." for the VIPs this core holds now
KCONF=/etc/keepalived/keepalived.conf
case "$1" in
  start)
    pgrep -x keepalived >/dev/null && { echo "keepalived already running"; exit 0; }
    keepalived -n -l -D -f "$KCONF" >>/var/log/keepalived.log 2>&1 &
    echo "keepalived started"
    ;;
  stop)
    pkill -x keepalived
    i=0; while pgrep -x keepalived >/dev/null && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
    echo "keepalived stopped"
    ;;
  status)
    printf 'MASTER for:'
    for d in /sys/class/net/vlan*; do
      v="${d##*/vlan}"
      ip -4 addr show dev "vlan$v" | grep -q "10\.10\.$v\.1/24" && printf ' vlan%s' "$v"
    done
    echo
    ;;
  *) echo "usage: $0 start|stop|status" >&2; exit 2 ;;
esac
