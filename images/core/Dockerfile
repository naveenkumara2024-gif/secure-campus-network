# images/core/Dockerfile - CORE-SW1/2 image.
# FRR 10.4.5 (Alpine 3.22) per CLAUDE.md section 4, plus nftables (inter-VLAN
# policy, M3), keepalived (VRRP, M4) and tcpdump.
FROM quay.io/frrouting/frr:10.4.5
RUN apk add --no-cache nftables keepalived tcpdump
