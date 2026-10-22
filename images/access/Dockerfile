# images/access/Dockerfile - access-switch image (ACC-SW1/2/3, SRV-SW).
# alpine:3.20 per CLAUDE.md section 4, plus full iproute2 (bridge VLAN filtering;
# BusyBox `ip` has no `bridge` command), nftables for Campus Guardian, tcpdump.
FROM alpine:3.20
RUN apk add --no-cache iproute2 nftables tcpdump python3
CMD ["tail", "-f", "/dev/null"]
