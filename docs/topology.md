# Campus topology

Source of truth: [`campus.clab.yml`](../campus.clab.yml). This diagram is the output of
`containerlab graph -t campus.clab.yml --mermaid --offline`, regrouped by layer and
annotated with the CLAUDE.md section 3 subnets. The live view is VS Code TopoViewer.

```mermaid
graph TD
  subgraph WAN
    isp1 ---|"internet transit 192.0.2.0/30"| isp2
  end
  subgraph Edge
    edge1
    edge2
  end
  subgraph Branch
    branch-host
  end
  subgraph Core
    core1 ===|"LACP bond: eth-peer1 + eth-peer2, trunk + 10.10.200.0/30"| core2
  end
  subgraph Access
    acc1
    acc2
    acc3
    srv-sw
  end
  subgraph Endpoints
    pc-student
    attacker
    phone
    pc-faculty
    pc-staff
    pc-library
    pc-guest
  end
  subgraph ServerFarm["Server farm, VLAN 40"]
    dhcp
    dns
    radius
    syslog
    ntp
    web
  end

  edge1 ---|"203.0.113.0/30"| isp1
  edge2 ---|"198.51.100.0/30"| isp2
  edge2 ---|"172.16.30.0/24"| branch-host
  core1 ---|"10.10.211.0/30"| edge1
  core2 ---|"10.10.212.0/30"| edge2

  acc1 ---|eth-up1| core1
  acc1 -.-|eth-up2| core2
  acc2 ---|eth-up1| core1
  acc2 -.-|eth-up2| core2
  acc3 ---|eth-up1| core1
  acc3 -.-|eth-up2| core2
  srv-sw ---|eth-up1| core1
  srv-sw -.-|eth-up2| core2

  acc1 ---|"p1 VLAN 20"| pc-student
  acc1 ---|"p2 VLAN 20"| attacker
  acc1 ---|"p3 VLAN 100"| phone
  acc2 ---|"p1 VLAN 10"| pc-faculty
  acc2 ---|"p2 VLAN 50"| pc-staff
  acc3 ---|"p1 VLAN 30"| pc-library
  acc3 ---|"p2 VLAN 60"| pc-guest
  srv-sw ---|p1| dhcp
  srv-sw ---|p2| dns
  srv-sw ---|p3| radius
  srv-sw ---|p4| syslog
  srv-sw ---|p5| ntp
  srv-sw ---|p6| web
```

Dotted uplinks are the ones RSTP is expected to hold in DISCARDING once M5 is built;
which uplink actually blocks is decided by the protocol at run time.
