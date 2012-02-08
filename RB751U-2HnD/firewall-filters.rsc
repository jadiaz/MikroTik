:log info "Enable connection tracking.";
/ip firewall connection tracking set enabled=yes;

:log info "Adding bogon address list";
/ip firewall address-list
add list="illegal-addr" address=0.0.0.0/8 comment="illegal addresses"
add list="illegal-addr" address=10.0.0.0/8
add list="illegal-addr" address=127.0.0.0/8
add list="illegal-addr" address=169.254.0.0/16
add list="illegal-addr" address=172.16.0.0/12
add list="illegal-addr" address=192.0.0.0/24
add list="illegal-addr" address=192.0.2.0/24
add list="illegal-addr" address=192.168.0.0/16
add list="illegal-addr" address=198.18.0.0/15
add list="illegal-addr" address=198.51.100.0/24
add list="illegal-addr" address=203.0.113.0/24
add list="illegal-addr" address=224.0.0.0/4
add list="nat-addr" address=192.168.89.0/24 comment="src-nated local network hosts";

:log info "Enable NAT traversal detection";
/ip firewall mangle add action=mark-packet chain=prerouting comment="detect NAT traversal" in-interface=ether1-gateway dst-address-list=nat-addr new-packet-mark=nat-traversal passthrough=no;

:log info "Setting firewall filters";
/ip firewall filter

add action=accept chain=forward comment="allow traffic between lan clients" in-interface=bridge-local out-interface=bridge-local
add action=accept chain=input comment="allow local traffic (between routers)" dst-address-type=local src-address-type=local
add action=jump chain=input comment="allow lan dhcp" jump-target=dhcp in-interface=bridge-local protocol=udp src-port=68 dst-port=67
add action=jump chain=forward comment="sanity check" jump-target=sanity-check
add action=jump chain=input comment="drop packets not destined for router" dst-address-type=!local jump-target=drop
add action=jump chain=input comment="limit icmp to router" jump-target=ICMP protocol=icmp
add action=jump chain=input comment="allow some router services from LAN" jump-target=local-services in-interface=bridge-local
add action=jump chain=input comment="allow some router services from Internet" jump-target=public-services in-interface=ether1-gateway
add action=jump chain=input comment="drop everything else" jump-target=drop


#add action=accept chain=input comment="local access to router for Winbox" disabled=no dst-port=8291 protocol=tcp src-address-list=local
#add action=accept chain=input comment="local access to router via LAN" disabled=no in-interface=ether2-master-local
#add action=accept chain=input comment="local access to router via WLAN" disabled=yes in-interface=wlan1
#add action=accept chain=inbound comment="allow local traffic between lan and wan" in-interface=bridge-local out-interface=bridge-local
#add action=jump chain=input comment="treat all traffic equally" disabled=no jump-target=inbound
#add action=jump chain=forward comment="treat all traffic equally" disabled=no jump-target=inbound


# Chain - Sanity Check
add action=jump chain=sanity-check comment="deny illegal nat traversal" jump-target=drop packet-mark=nat-traversal
add action=add-src-to-address-list chain=sanity-check comment="block TCP null scan" address-list=blocked-addr address-list-timeout=1d protocol=tcp tcp-flags=fin,psh,urg,!syn,!rst,!ack
add action=add-src-to-address-list chain=sanity-check comment="block TCP Xmas scan" address-list=blocked-addr address-list-timeout=1d protocol=tcp tcp-flags=!fin,!syn,!rst,!psh,!ack,!urg
add action=jump chain=sanity-check comment="drop blocked-address" jump-target=drop protocol=tcp src-address-list=blocked-addr
add action=jump chain=sanity-check comment="drop TCP RST" jump-target=drop protocol=tcp tcp-flags=rst
add action=jump chain=sanity-check comment="drop TCP SYN+FIN" jump-target=drop protocol=tcp tcp-flags=fin,syn
add action=jump chain=sanity-check comment="drop invalid connection packets to router" connection-state=invalid jump-target=drop
add action=accept chain=sanity-check comment="accept established connections" connection-state=established
add action=accept chain=sanity-check comment="accept related connections" connection-state=related
add action=jump chain=sanity-check comment="drop all traffic that goes to multicast/broadcast addresses" dst-address-type=broadcast,multicast jump-target=drop
add action=jump chain=sanity-check comment="drop illegal destination addresses" dst-address-list=illegal-addr dst-address-type=!local jump-target=drop in-interface=bridge-local
add action=jump chain=sanity-check comment="drop everything that does not come from a local address" jump-target=drop in-interface=bridge-local src-address-list=!local-addr
add action=jump chain=sanity-check comment="drop illegal source addresses" jump-target=drop in-interface=ether1-gateway src-address-list=illegal-addr
add action=jump chain=sanity-check comment="drop all traffic that comes from multicast/broadcast addresses" jump-target=drop src-address-type=broadcast,multicast

# Chain - DHCP
add action=accept chain=dhcp dst-address=255.255.255.255 src-address=0.0.0.0
add action=accept chain=dhcp dst-address-type=local src-address=0.0.0.0
add action=accept chain=dhcp dst-address-type=local src-address-list=local-addr

# Chain - ICMP
add action=accept chain=ICMP comment="0:0 and limit for 5 pac/s" disabled=no icmp-options=0:0-255 limit=5,5 protocol=icmp
add action=accept chain=ICMP comment="3:3 and limit for 5 pac/s" disabled=no icmp-options=3:3 limit=5,5 protocol=icmp
add action=accept chain=ICMP comment="3:4 and limit for 5 pac/s" disabled=no icmp-options=3:4 limit=5,5 protocol=icmp
add action=accept chain=ICMP comment="8:0 and limit for 5 pac/s" disabled=no icmp-options=8:0-255 limit=5,5 protocol=icmp
add action=accept chain=ICMP comment="11:0 and limit for 5 pac/s" disabled=no icmp-options=11:0-255 limit=5,5 protocol=icmp
add action=drop chain=ICMP comment="drop everything else" disabled=no protocol=icmp

# Chain - Local Services
add action=accept chain=local-services comment="SSH (22/TCP)" dst-port=22 protocol=tcp
add action=accept chain=local-services comment="DNS" dst-port=53 protocol=udp
add action=accept chain=local-services dst-port=53 protocol=tcp
add action=accept chain=local-services comment="Winbox (8291/TCP)" dst-port=8291 protocol=tcp disabled=no
add action=accept chain=local-services comment="SNMP" disabled=no dst-port=161 protocol=udp
add action=accept chain=local-services comment="FTP" disabled=no dst-port=21 protocol=tcp
add action=accept chain=local-services comment="NTP" disabled=no dst-port=123 protocol=udp
add action=accept chain=local-services comment="Neighbor discovery" disabled=no dst-port=5678 protocol=udp
add action=log chain=local-services comment="Local services - investigate" 
add action=drop chain=local-services disabled=yes

# Chain - Public Services
add action=accept chain=public-services comment="SSH (22/TCP)" disabled=yes dst-port=22 protocol=tcp
add action=accept chain=public-services comment="PPTP (1723/TCP)" dst-port=1723 protocol=tcp
add action=accept chain=public-services comment="Winbox (8291/TCP)" dst-port=8291 protocol=tcp
add action=accept chain=public-services comment="GRE for PPTP" protocol=gre
add action=log chain=public-services comment="Public Services - investigate"
add action=drop chain-public-services disabled=yes

# Chain - Email
add action=accept chain=email comment="Allow SMTP" disabled=no dst-port=25 protocol=tcp src-address-list=local
add action=accept chain=email comment="Allow POP" disabled=no dst-port=110 protocol=tcp src-address-list=local
add action=accept chain=email comment="Allow gMail SMTP over SSL" disabled=no dst-port=465 protocol=tcp src-address-list=local
add action=accept chain=email comment="Allow gMail SMTP over SSL" disabled=no dst-port=587 protocol=tcp src-address-list=local
add action=accept chain=email comment="Allow IMAP4 protocol over TLS/SSL" disabled=no dst-port=993 protocol=tcp src-address-list=local
add action=accept chain=email comment="Allow POPS protocol over TLS/SSL" disabled=no dst-port=995 protocol=tcp src-address-list=local 
add action=drop chain=email comment="drop all other smtp servers" disabled=no protocol=tcp dst-port=25 src-address-list=local dst-address=0.0.0.0/0

# Chain - Web
add action=accept chain=web comment="Allow HTTP" disabled=no dst-port=80 protocol=tcp src-address-list=local
add action=accept chain=web comment="Allow HTTPS" disabled=no dst-port=443 protocol=tcp src-address-list=local

# Chain - Messaging
add action=accept chain=messaging comment="Allow AOL/AIM Instant Messaging" disabled=no dst-port=5190 protocol=tcp src-address-list=local
add action=accept chain=messaging comment="Allow IIRC Instant Messaging" disabled=no dst-port=6667 protocol=tcp src-address-list=local
add action=accept chain=messaging comment="Allow Skype" disabled=no protocol=udp src-address-list=local src-port=61575
add action=accept chain=messaging comment="Allow Google+ Hangout" disabled=no dst-port=19302-19305 protocol=udp src-address-list=local

# Chain - Drop
add action=log chain=drop comment="Drop - investigate" disabled=no
add action=drop chain=drop disabled=yes;


:log info "Finished applying filters to firewall.";
:put "";
:put "Finished applying filters to firewall. Please check system log.";
:put "";
