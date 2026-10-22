# images/vpn/Dockerfile - EDGE-R1/2 image: strongSwan 6 (PQ-IPsec) + FRR + nftables.
# Built by `make images` as campus/vpn:latest.
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      strongswan strongswan-swanctl libcharon-extra-plugins \
      libstrongswan-extra-plugins iproute2 iputils-ping nftables frr \
 && rm -rf /var/lib/apt/lists/*
# Ensure the 'ml' plugin (ML-KEM, FIPS 203) is enabled; openssl plugin (OpenSSL>=3.5) also provides it.
# (verified in M8; containerlab overrides CMD with nodes/edge/init.sh)
CMD ["sleep", "infinity"]
