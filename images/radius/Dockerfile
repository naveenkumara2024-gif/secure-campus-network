# images/radius/Dockerfile - FreeRADIUS server (VLAN 40, 10.10.40.12).
# The upstream image (Ubuntu 22.04, FreeRADIUS 3.2.10) has no `ip`/`ping`,
# which the init script needs to address eth1.
FROM freeradius/freeradius-server:3.2.10
RUN apt-get update \
 && apt-get install -y --no-install-recommends iproute2 iputils-ping \
 && rm -rf /var/lib/apt/lists/*
