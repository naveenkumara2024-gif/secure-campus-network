# End-to-End Secure Campus Network Architecture with High Availability
## Comprehensive Project Documentation & Implementation Guide

---

## 1. Project Context & Objectives

### 1.1 Objective
This project models an enterprise-grade, highly available, and secure campus network tailored for a university or multi-building corporate environment. The system is designed to fulfill three primary pillars:
1. **High Availability (HA):** Eliminates single points of failure across all layers (access, core, server farm, and WAN edge).
2. **Defense-in-Depth Security:** Implements L2/L3 security controls, strict VLAN segmentation, encrypted WAN communications, and centralized AAA management.
3. **Scalability & Manageability:** Features standardized addressing, structured hierarchical topology, and centralized monitoring via Syslog and NTP.

---

## 2. Architectural Design

### 2.1 Collapsed Core Topology
The network uses a **Collapsed Core Architecture** where the Core and Distribution layers are combined into a redundant pair of Layer 3 multilayer switches (`CORE-SW1` and `CORE-SW2`).

```
                         ISP-1 Cloud        ISP-2 Cloud
                             |                   |
                        EDGE-R1 ============ EDGE-R2      (HSRP, NAT, IPsec VPN)
                             |                   |
                       (L3 Routed / OSPF Area 0)
                             |                   |
                       CORE-SW1 ===EtherChannel=== CORE-SW2
                       (Active: 10,20,40,100)      (Active: 30,50,60,99)
                        /        |        \             |
                       /         |         \            |
                 ACC-SW1     ACC-SW2     ACC-SW3     SRV-SW
                (Admin)     (Academic)  (Library)   (Server Farm)
                    |            |           |           |
                 PCs/AP1     PCs/AP2     PCs/AP3    DNS/DHCP/WEB/
                                                      MAIL/AAA/SYSLOG
```

---

## 3. High-Availability Mechanisms

| Mechanism | Protocol / Technology | Scope | Target Failure Scenario |
|---|---|---|---|
| **Link Bundling** | LACP (EtherChannel) | `CORE-SW1` ↔ `CORE-SW2` | Single physical link failure |
| **L2 Loop Prevention** | Rapid PVST+ (802.1w) | Access ↔ Dual Core Uplinks | Switch loop prevention, sub-second failover |
| **Gateway Redundancy** | HSRP (v2) | Core SVI Interfaces | Core Switch failure (Virtual IP load sharing) |
| **Dynamic WAN Routing** | OSPF Area 0 | Core Switches ↔ Edge Routers | Router/Path failure, auto-convergence |
| **Dual ISP Redundancy** | Dual Default Routes | Edge Routers ↔ ISPs | ISP outage / upstream link failure |

---

## 4. Security Framework (Defense-in-Depth)

| Layer | Threat | Mitigation Strategy |
|---|---|---|
| **Access Port** | MAC Flooding / Unauthorized Device | Port Security (Sticky MAC, max limit, `restrict`) |
| **L2 Infrastructure** | Rogue DHCP Server | DHCP Snooping (Trusted/Untrusted interfaces) |
| **L2 Infrastructure** | ARP Poisoning / Man-in-the-Middle | Dynamic ARP Inspection (DAI) bound to DHCP Snooping |
| **Spanning-Tree** | STP Root Bridge Hijacking | BPDU Guard & PortFast on access ports; fixed primary root on Cores |
| **Inter-VLAN** | Lateral Movement / Unauthorized Access | Extended IP Access Lists (ACLs) on SVIs |
| **Perimeter / WAN** | Unsolicited Inbound Traffic | Outside Extended ACLs & NAPT/PAT |
| **Site-to-Site** | Eavesdropping over Public Internet | IPsec VPN (IKEv1/AES-256/SHA256/DH Group 14) |
| **Management** | Unauthorized Switch Access | SSHv2, VTY Access ACLs, AAA via RADIUS with local fallback |

---

## 5. Network Addressing & Subnet Plan

### 5.1 VLAN Allocation & Gateway Plan

| VLAN | Name | Subnet | HSRP VIP | Active Core | Standby Core |
|---|---|---|---|---|---|
| 10 | FACULTY-ADMIN | 10.10.10.0/24 | 10.10.10.1 | CORE-SW1 (.2) | CORE-SW2 (.3) |
| 20 | STUDENTS | 10.10.20.0/24 | 10.10.20.1 | CORE-SW1 (.2) | CORE-SW2 (.3) |
| 30 | LIBRARY | 10.10.30.0/24 | 10.10.30.1 | CORE-SW2 (.3) | CORE-SW1 (.2) |
| 40 | SERVER-FARM | 10.10.40.0/24 | 10.10.40.1 | CORE-SW1 (.2) | CORE-SW2 (.3) |
| 50 | WIFI-STAFF | 10.10.50.0/24 | 10.10.50.1 | CORE-SW2 (.3) | CORE-SW1 (.2) |
| 60 | WIFI-GUEST | 10.10.60.0/24 | 10.10.60.1 | CORE-SW2 (.3) | CORE-SW1 (.2) |
| 99 | MGMT-NATIVE | 10.10.99.0/24 | 10.10.99.1 | CORE-SW2 (.3) | CORE-SW1 (.2) |
| 100 | VOICE | 10.10.100.0/24 | 10.10.100.1 | CORE-SW1 (.2) | CORE-SW2 (.3) |

### 5.2 Point-to-Point L3 Interconnects

| Segment | Subnet | Role |
|---|---|---|
| `CORE-SW1` ↔ `CORE-SW2` | 10.10.200.0/30 | L3 Backup Link (Port-channel 1) |
| `CORE-SW1` ↔ `EDGE-R1` | 10.10.211.0/30 | OSPF Link |
| `CORE-SW2` ↔ `EDGE-R2` | 10.10.212.0/30 | OSPF Link |
| `EDGE-R1` ↔ `ISP-1` | 203.0.113.0/30 | Public Link |
| `EDGE-R2` ↔ `ISP-2` | 198.51.100.0/30 | Public Link |
| Remote Branch LAN | 172.16.30.0/24 | Protected Site across IPsec VPN |

---

## 6. Comprehensive Implementation Steps

### Step 1: Core Switch Base Hardening
```cisco
enable
configure terminal
hostname CORE-SW1
no ip domain-lookup
service password-encryption
enable secret Campus@Core1!
security passwords min-length 8
username netadmin privilege 15 secret Admin@2026
ip domain-name campus.local
crypto key generate rsa modulus 1024
ip ssh version 2
line console 0
 password Campus@Con1!
 login
 exec-timeout 5 0
line vty 0 15
 login local
 transport input ssh
banner motd # Authorized Access Only #
exit
```

### Step 2: Layer 2 VLAN & EtherChannel Setup
```cisco
vtp mode transparent
vlan 10,20,30,40,50,60,99,100

interface range GigabitEthernet0/23 - 24
 switchport trunk encapsulation dot1q
 switchport mode trunk
 switchport trunk native vlan 99
 channel-group 1 mode active
exit

interface Port-channel1
 switchport trunk encapsulation dot1q
 switchport mode trunk
 switchport trunk native vlan 99
exit
```

### Step 3: Rapid PVST+ Tuning
```cisco
! On CORE-SW1
spanning-tree mode rapid-pvst
spanning-tree vlan 10,20,40,100 root primary
spanning-tree vlan 30,50,60,99 root secondary

! On Access Switches (User-facing ports)
interface range FastEthernet0/1 - 20
 spanning-tree portfast
 spanning-tree bpduguard enable
exit
```

### Step 4: Layer 3 SVIs and HSRP Configuration
```cisco
! On CORE-SW1
ip routing
interface Vlan10
 ip address 10.10.10.2 255.255.255.0
 standby version 2
 standby 10 ip 10.10.10.1
 standby 10 priority 110
 standby 10 preempt
 standby 10 authentication md5 key-string HsrpCampus1
exit
```

### Step 5: L2 Hardening (Port Security, DHCP Snooping, DAI)
```cisco
! Access Switch Port Security
interface range FastEthernet0/1 - 20
 switchport mode access
 switchport access vlan 20
 switchport voice vlan 100
 switchport port-security
 switchport port-security maximum 2
 switchport port-security mac-address sticky
 switchport port-security violation restrict
exit

! Core Switches - DHCP Snooping & Dynamic ARP Inspection
ip dhcp snooping
ip dhcp snooping vlan 10,20,30,40,50,60,100
no ip dhcp snooping information option
ip arp inspection vlan 10,20,30,40,50,60,100

interface GigabitEthernet0/10
 description Link-to-Server-Farm
 ip dhcp snooping trust
 ip arp inspection trust
exit
```

### Step 6: Site-to-Site IPsec VPN Configuration (`EDGE-R1`)
```cisco
crypto isakmp policy 10
 encryption aes 256
 hash sha256
 authentication pre-share
 group 14
crypto isakmp key CampusVpnKey2026 address 198.51.100.2

crypto ipsec transform-set CAMPUS-TS esp-aes 256 esp-sha256-hmac

access-list 110 permit ip 10.10.0.0 0.0.255.255 172.16.30.0 0.0.0.255

crypto map CAMPUS-VPN 10 ipsec-isakmp
 set peer 198.51.100.2
 set transform-set CAMPUS-TS
 match address 110

interface GigabitEthernet0/0
 crypto map CAMPUS-VPN
exit
```

---

## 7. Verification & Proof of Concept Commands

| Objective | Command | Expected Result |
|---|---|---|
| **EtherChannel Integrity** | `show etherchannel summary` | State should show `SU` (In Use / Layer 2) |
| **HSRP Role Verification** | `show standby brief` | Shows local device as `Active` for designated VLANs and `Standby` for secondary VLANs |
| **DHCP Binding Table** | `show ip dhcp snooping binding` | Lists MAC-to-IP-to-VLAN mappings dynamically learned on access ports |
| **DAI Validation** | `show ip arp inspection statistics` | Confirms valid ARP packets forwarded and spoofed ARP attempts dropped |
| **IPsec Tunnel Status** | `show crypto ipsec sa` | Encaps/Decaps counters incrementing during cross-tunnel pings |
| **OSPF Neighbor State** | `show ip ospf neighbor` | Shows state `FULL/BDR` or `FULL/DR` with edge routers and peer core switch |

---
*Documentation compiled for Campus Network Architecture Design.*