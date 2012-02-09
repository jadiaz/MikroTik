:log info "Clearing old filters.";
:foreach r in=[/ip firewall filter find] do={
  /ip firewall filter remove numbers=$r;
}

:log info "Clearing old address lists.";
:foreach a in=[/ip firewall address-list find] do={
  /ip firewall address-list remove numbers=$a;
}

:log info "Clearing previous mangles.";
:foreach m in=[/ip firewall mangle find] do={
  /ip firewall mangle remove numbers=$m;
}

:log info "Enable connection tracking.";
/ip firewall connection tracking set enabled=yes;

:local lanNetworkAddress "192.168.89.0";
:local lanNetworkBits "24";
:log info "Adding $lanNetworkAddress/$lanNetworkBits to local address list.";
/ip firewall address-list add address="$lanNetworkAddress/$lanNetworkBits" comment="lan" disabled=no list=local-addr;

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
add list="nat-addr" address=192.168.89.0/24 comment="src-nated lan hosts";


:log info "Enable NAT traversal detection";
/ip firewall mangle add action=mark-packet chain=prerouting comment="detect NAT traversal" in-interface=ether1-gateway dst-address-list=nat-addr new-packet-mark=nat-traversal passthrough=no;

:log info "Setting firewall filters";
/ip firewall filter

add action=accept chain=forward comment="Allow lan traffic" disabled=no in-interface=bridge-local out-interface=bridge-local
add action=jump chain=input comment="Check connection state" disabled=no in-interface=ether1-gateway jump-target=detect-connection-state
add action=jump chain=input comment="Check for port scanning" disabled=no jump-target=detect-port-scan
add action=jump chain=input comment="Check for ping flooding" disabled=no jump-target=detect-ping-flood protocol=icmp
add action=jump chain=input comment="Allow router services on the lan" disabled=no in-interface=bridge-local jump-target=router-services-lan
add action=jump chain=input comment="Allow router services on the wan" disabled=yes in-interface=ether1-gateway jump-target=router-services-wan
add action=log chain=input disabled=yes log-prefix=Logging
add action=jump chain=input comment=Drop disabled=no dst-address-type=!local jump-target=drop
add action=jump chain=forward comment="Check connection state" disabled=no jump-target=detect-connection-state
add action=jump chain=forward comment="Check for invalid addresses" disabled=no jump-target=detect-invalid-address
add action=jump chain=forward comment="Allow web traffic" disabled=no jump-target=web
add action=jump chain=forward comment="Allow email" disabled=no jump-target=email
add action=jump chain=forward comment="allow messaging" disabled=no jump-target=messaging
add action=jump chain=forward comment="allow clients" disabled=no jump-target=clients
add action=log chain=forward disabled=no log-prefix=Logging
add action=drop chain=drop comment="FINAL DROP -- ALL --" disabled=no
add action=accept chain=detect-connection-state comment="Established connections" connection-state=established disabled=no
add action=accept chain=detect-connection-state comment="Related connections" connection-state=related disabled=no
add action=jump chain=detect-connection-state comment="Invalid connections" connection-state=invalid disabled=no jump-target=drop
add action=add-src-to-address-list address-list=blocked-addr address-list-timeout=1d chain=detect-port-scan comment="NMAP FIN Stealth scan" disabled=no protocol=tcp
add action=add-src-to-address-list address-list=blocked-addr address-list-timeout=1d chain=detect-port-scan comment="TCP Xmas scan" disabled=no protocol=tcp
add action=add-src-to-address-list address-list=blocked-addr address-list-timeout=2w chain=detect-port-scan comment="NMAP FIN Stealth scan" disabled=no protocol=tcp
add action=add-src-to-address-list address-list=blocked-addr address-list-timeout=2w chain=detect-port-scan comment="SYN/FIN scan" disabled=no protocol=tcp
add action=add-src-to-address-list address-list=blocked-addr address-list-timeout=0s chain=detect-port-scan comment="SYN/RST scan" disabled=no protocol=tcp
add action=jump chain=detect-port-scan comment="deny illegal nat traversal" disabled=yes jump-target=drop packet-mark=nat-traversal
add action=jump chain=detect-port-scan comment="Drop port scanners" disabled=no jump-target=drop src-address-list=blocked-addr
add action=jump chain=detect-invalid-address comment="Drop blacklisted ip addresses" disabled=no jump-target=drop protocol=tcp src-address-list=blocked-addr
add action=jump chain=detect-invalid-address comment="Drop inbound multicast/broadcast" disabled=no jump-target=drop src-address-type=broadcast,multicast
add action=jump chain=detect-invalid-address comment="Drop outbound multicast/broadcast" disabled=no dst-address-type=broadcast,multicast jump-target=drop
add action=jump chain=detect-invalid-address comment="Drop outbound to blacklisted addresses" disabled=no dst-address-list=illegal-addr dst-address-type=!local in-interface=bridge-local jump-target=drop
add action=jump chain=detect-invalid-address comment="Drop anything not originating from local addresses" disabled=no in-interface=bridge-local jump-target=drop src-address-list=!local-addr
add action=jump chain=detect-invalid-address comment="Drop inbound from blacklisted addresses" disabled=no in-interface=ether1-gateway jump-target=drop src-address-list=illegal-addr
add action=accept chain=detect-ping-flood comment="0:0 and limit for 5 pac/s" disabled=no icmp-options=0:0-255 limit=5,5 protocol=icmp
add action=accept chain=detect-ping-flood comment="3:3 and limit for 5 pac/s" disabled=no icmp-options=3:3 limit=5,5 protocol=icmp
add action=accept chain=detect-ping-flood comment="3:4 and limit for 5 pac/s" disabled=no icmp-options=3:4 limit=5,5 protocol=icmp
add action=accept chain=detect-ping-flood comment="8:0 and limit for 5 pac/s" disabled=no icmp-options=8:0-255 limit=5,5 protocol=icmp
add action=accept chain=detect-ping-flood comment="11:0 and limit for 5 pac/s" disabled=no icmp-options=11:0-255 limit=5,5 protocol=icmp
add action=drop chain=detect-ping-flood comment="drop everything else" disabled=no protocol=icmp
add action=accept chain=router-services-lan comment="SSH (22/TCP)" disabled=no dst-port=22 protocol=tcp
add action=accept chain=router-services-lan comment=DNS disabled=no dst-port=53 protocol=udp
add action=accept chain=router-services-lan disabled=no dst-port=53 protocol=tcp
add action=accept chain=router-services-lan comment="Winbox (8291/TCP)" disabled=no dst-port=8291 protocol=tcp
add action=accept chain=router-services-lan comment=SNMP disabled=yes dst-port=161 protocol=udp
add action=accept chain=router-services-lan comment=FTP disabled=no dst-port=21 protocol=tcp
add action=accept chain=router-services-lan comment=TCP disabled=no dst-port=23 protocol=tcp
add action=accept chain=router-services-lan comment=NTP disabled=no dst-port=123 protocol=udp
add action=accept chain=router-services-lan comment="Neighbor discovery" disabled=no dst-port=5678 protocol=udp
add action=accept chain=router-services-wan comment="SSH (22/TCP)" disabled=no dst-port=22 protocol=tcp
add action=accept chain=router-services-wan comment="PPTP (1723/TCP)" disabled=no dst-port=1723 protocol=tcp
add action=accept chain=router-services-wan comment="Winbox (8291/TCP)" disabled=no dst-port=8291 protocol=tcp
add action=accept chain=router-services-wan comment="GRE for PPTP" disabled=no protocol=gre
add action=accept chain=web comment="Allow HTTP" disabled=no dst-port=80 protocol=tcp src-address-list=local-addr
add action=accept chain=web comment="Allow HTTPS" disabled=no dst-port=443 protocol=tcp src-address-list=local-addr
add action=accept chain=email comment="Allow SMTP" disabled=no dst-port=25 protocol=tcp src-address-list=local-addr
add action=accept chain=email comment="Allow POP" disabled=no dst-port=110 protocol=tcp src-address-list=local-addr
add action=accept chain=email comment="Allow gMail SMTP over SSL" disabled=no dst-port=465 protocol=tcp src-address-list=local-addr
add action=accept chain=email comment="Allow gMail SMTP over SSL" disabled=no dst-port=587 protocol=tcp src-address-list=local-addr
add action=accept chain=email comment="Allow IMAP4 protocol over TLS/SSL" disabled=no dst-port=993 protocol=tcp src-address-list=local-addr
add action=accept chain=email comment="Allow POPS protocol over TLS/SSL" disabled=no dst-port=995 protocol=tcp src-address-list=local-addr
add action=accept chain=messaging comment="Allow AOL/AIM Instant Messaging" disabled=no dst-port=5190 protocol=tcp src-address-list=local-addr
add action=accept chain=messaging comment="Allow IIRC Instant Messaging" disabled=no dst-port=6667 protocol=tcp src-address-list=local-addr
add action=accept chain=messaging comment="Allow Skype" disabled=no protocol=udp src-address-list=local-addr src-port=61575
add action=accept chain=messaging comment="Allow Google+ Hangout" disabled=no dst-port=19302-19305 protocol=udp src-address-list=local-addr
add action=accept chain=clients comment="Allow Dropbox" disabled=no dst-port=17500 protocol=tcp src-address-list=local-addr
add action=accept chain=clients disabled=no dst-port=17500 protocol=udp src-address-list=local-addr

:log info "Finished applying filters to firewall.";
:put "";
:put "Finished applying filters to firewall. Please check system log.";
:put "";
