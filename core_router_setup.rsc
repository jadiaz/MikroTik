#-------------------------------------------------------------------------------
#
# The purpose of this script is to create a standard SOHO type
# configuration for the RB751U which can be built on by the user.
#
#-------------------------------------------------------------------------------

# Set the name of the router
:local systemIdentity "MyRouter";

# Secure your RouterOS! Set the password you would like to use when logging on as 'admin'.
:local adminPassword "ChangeMe!";

# Time Servers (NTP)
:local ntpA "173.230.149.23";
:local ntpB "198.110.48.12";

# Name Servers (DNS) - set to OpenDNS. This should be set to a set of servers that are local and FAST 
:local nsA "216.116.96.2";
:local nsB "216.52.254.33";
:local nsC "68.111.16.30";

# NAT (true/false) - Set to '1' unless you know what you are doing!
:local natEnabled 1;

# DHCP - Automatically set if package is installed
:local dhcpEnabled 0;
:local dhcpServer "dhcp-server"
:local poolStart "192.168.50.1";
:local poolEnd "192.168.50.100";

:local lanAddress "192.168.50.1";
:local lanNetworkAddress "192.168.50.0";
:local lanNetworkBits "24";


# Interfaces
:local ether1Interface "ether1-gateway";
:local ether2Interface "ether2-master-local";
:local ether3Interface "ether3-slave-local";
:local ether4Interface "ether4-slave-local";
:local ether5Interface "ether5-slave-local";

# Timezone
:local timeZone "America/Phoenix";

#-------------------------------------------------------------------------------
#
# Apply configuration.
# these commands are executed after installation or configuration reset
#
#-------------------------------------------------------------------------------

/system logging action set memory memory-lines=500

# Clearing out pre-existing settings
/ip dhcp-client remove [find];
/interface bridge remove [find];
/interface bridge port remove [find];
/ip address remove [find];
/ip dhcp-server remove [find];
/ip pool remove [find];
/ip dhcp-server network remove [find];
/ip firewall nat remove [find];
/ip ipsec proposal remove [find];
/ppp profile remove [find];

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

:log info "Clearing previous layer-7.";
:foreach m in=[/ip firewall layer7-protocol find] do={
  /ip firewall layer7-protocol remove numbers=$m;
}


# Check for the required packages
:if ([:len [/system package find name="dhcp" !disabled]] != 0) do={
  :log info "DHCP package found. Enabling DHCP server on router.";
	:set dhcpEnabled 1;
}

:log info "Setting timezone.";
/system clock set time-zone=$timeZone;

:log info "Setting up the time server client.";
/system ntp client set enabled=yes mode=unicast primary-ntp=$ntpA secondary-ntp=$ntpB;

:log info "Setting the system name";
/system identity set name "$systemIdentity";

:log info "Setting admin password";
/user set admin password="$adminPassword";


#-------------------------------------------------------------------------------
#
# Setting the ethernet interfaces
# Ethernet Port 1 is used as the WAN port and is designated the gateway to DSL/Cable Modem
# DHCP client and masquerde is enabled on ether1
# Ethernet port 2 is used as the switch master for the remain three ports
#
#-------------------------------------------------------------------------------

# Setup the wired interface(s)
/interface set ether1 name="$ether1Interface";

:if ( $dhcpEnabled = 1 ) do={
  :log info "Setting up a dhcp client on the gateway interface";
  /ip dhcp-client add interface=$ether1Interface disabled=no comment="Gateway Interface. Connect to ISP modem." use-peer-dns=no use-peer-ntp=no add-default-route=no;
}

/interface ethernet {
  set ether2 name="$ether2Interface";
  set ether3 name="$ether3Interface" master-port=$ether2Interface;
  set ether4 name="$ether4Interface" master-port=$ether2Interface;
  set ether5 name="$ether5Interface" master-port=$ether2Interface;
}

#-------------------------------------------------------------------------------
#
# DHCP Server
# configure the server on the bridge interface for handing out ip to both
# lan and wlan. Address pool is defined above with $poolStart and $poolEnd.
#
#-------------------------------------------------------------------------------

:log info "Setting LAN address to $lanAddress/$lanNetworkBits";
/ip address add address="$lanAddress/$lanNetworkBits" interface=$ether2Interface network=$lanNetworkAddress comment="core router LAN address";

:log info "Setting DNS servers to $nsA and $nsB.";
/ip dns set allow-remote-requests=yes servers="$nsA,$nsB,$nsC";

:if ( $dhcpEnabled = 1 ) do={
  :log info "Setting DHCP server on interface, pool $poolStart-$poolEnd";
  /ip pool add name="local-dhcp-pool" ranges="$poolStart-$poolEnd";
  /ip dhcp-server add name="$dhcpServer" address-pool="local-dhcp-pool" interface=$ether2Interface disabled=no lease-time=3d;
  /ip dhcp-server network add address="$lanNetworkAddress/$lanNetworkBits" gateway=$lanAddress dns-server=$lanAddress comment="local DHCP network";
}

#-------------------------------------------------------------------------------
#
# Firewall
#
#-------------------------------------------------------------------------------

# Set up NAT
:log info "Setting up NAT on WAN interface ($ether1Interface)";
/ip firewall nat
add action=masquerade chain=srcnat comment="NAT" disabled=no out-interface=$ether1Interface
add action=dst-nat chain=dstnat comment="Xbox Live" dst-port=3074 in-interface=$ether1Interface protocol=tcp to-addresses=192.168.50.201-192.168.50.203 to-ports=3074
add action=dst-nat chain=dstnat comment="XBox Live" dst-port=88 in-interface=$ether1Interface protocol=udp to-addresses=192.168.50.201-192.168.50.203 to-ports=88
add action=dst-nat chain=dstnat comment="XBox Live" dst-port=3074 in-interface=$ether1Interface protocol=udp to-addresses=192.168.50.201-192.168.50.203 to-ports=3074
add action=dst-nat chain=dstnat comment="XBox Live" dst-port=53 in-interface=$ether1Interface protocol=udp to-addresses=192.168.50.201-192.168.50.203 to-ports=53
add action=dst-nat chain=dstnat comment="XBox Live" dst-port=500 in-interface=$ether1Interface protocol=udp to-addresses=192.168.50.201-192.168.50.203 to-ports=500
add action=dst-nat chain=dstnat comment="XBox Live" dst-port=3544 in-interface=$ether1Interface protocol=udp to-addresses=192.168.50.201-192.168.50.203 to-ports=3544
add action=dst-nat chain=dstnat comment="XBox Live" dst-port=4500 in-interface=$ether1Interface protocol=udp to-addresses=192.168.50.201-192.168.50.203 to-ports=4500;

# Enable connection tracking
:log info "Enable connection tracking.";
/ip firewall connection tracking set enabled=yes;

# Create LAN address list
:log info "Adding $lanNetworkAddress/$lanNetworkBits to local address list.";
/ip firewall address-list add address="$lanNetworkAddress/$lanNetworkBits" comment="lan" disabled=no list=local-addr;

# Bogon Addresses - Aggregated (August-2015)
:log info "Adding bogon addresses to a list";
/ip firewall address-list
add list="bogon-addr" address=0.0.0.0/8
add list="bogon-addr" address=10.0.0.0/8
add list="bogon-addr" address=100.64.0.0/10
add list="bogon-addr" address=127.0.0.0/8
add list="bogon-addr" address=169.254.0.0/16
add list="bogon-addr" address=172.16.0.0/12
add list="bogon-addr" address=192.0.0.0/24
add list="bogon-addr" address=192.0.2.0/24
add list="bogon-addr" address=192.168.0.0/16
add list="bogon-addr" address=198.18.0.0/15
add list="bogon-addr" address=198.51.100.0/24
add list="bogon-addr" address=203.0.113.0/24
add list="bogon-addr" address=224.0.0.0/3;

:log info "Enable NAT traversal detection";
/ip firewall mangle add action=mark-packet chain=prerouting comment="detect NAT traversal" in-interface=$ether1Interface dst-address-list=local-addr new-packet-mark=nat-traversal passthrough=no;

:log info "Setting firewall filters";
/ip firewall filter
add action=accept chain=forward comment="Allow lan traffic" in-interface=$ether2Interface out-interface=$ether2Interface
add action=accept chain=input comment="Allow established connection on input" connection-state=established,related
add action=jump chain=input comment="Check for dns recursion" in-interface=$ether1Interface jump-target=detect-dns-recursion
add action=jump chain=input comment="Check for port scanning" jump-target=detect-port-scan
add action=jump chain=input comment="Check for ping flooding" jump-target=detect-ping-flood protocol=icmp
add action=jump chain=input comment="Drop inbound to invalid address" dst-address-type=!local jump-target=drop
add action=jump chain=input comment="Allow router services on the wan" in-interface=$ether1Interface jump-target=router-services-wan
add action=jump chain=input comment="Allow router services on the lan" in-interface=$ether2Interface jump-target=router-services-lan
add action=drop chain=input comment="Drop everything else on the input" in-interface=$ether1Interface
add action=accept chain=forward comment="Allow established connections on forward" connection-state=established,related
add action=drop chain=forward comment="Drop invalid connections" connection-state=invalid
add action=jump chain=forward comment="Check for infected computers" jump-target=detect-virus
add action=jump chain=forward comment="Allow gaming services" jump-target=gaming
add action=jump chain=forward comment="Allow web traffic" jump-target=web
add action=jump chain=forward comment="Allow email" jump-target=email
add action=jump chain=forward comment="Allow outgoing VPN connections" jump-target=vpn
add action=jump chain=forward comment="Allow development" jump-target=developer-services
add action=jump chain=forward comment="Allow messaging" jump-target=messaging
add action=jump chain=forward comment="Allow video streaming services" jump-target=streaming disabled=yes
add action=jump chain=forward comment="Allow general electronics access" jump-target=electronics disabled=yes
add action=log chain=forward log-prefix="[ No Match ]"
add action=drop chain=drop
add action=jump jump-target=drop chain=detect-dns-recursion comment="Deny requests for DNS from internet" dst-port=53 protocol=tcp
add action=jump jump-target=drop chain=detect-dns-recursion comment="Deny requests for DNS from internet" dst-port=53 protocol=udp
add action=add-src-to-address-list address-list=port-scanners address-list-timeout=4w chain=detect-port-scan protocol=tcp psd=21,3s,3,1
add action=add-src-to-address-list address-list=port-scanners address-list-timeout=4w chain=detect-port-scan comment="NMAP FIN Stealth scan" protocol=tcp tcp-flags=fin,!syn,!rst,!psh,!ack,!urg
add action=add-src-to-address-list address-list=port-scanners address-list-timeout=4w chain=detect-port-scan comment="SYN/FIN scan" protocol=tcp tcp-flags=fin,syn
add action=add-src-to-address-list address-list=port-scanners address-list-timeout=4w chain=detect-port-scan comment="SYN/RST scan" protocol=tcp tcp-flags=syn,rst
add action=add-src-to-address-list address-list=port-scanners address-list-timeout=4w chain=detect-port-scan comment="TCP Xmas scan" protocol=tcp tcp-flags=fin,psh,urg,!syn,!rst,!ack
add action=add-src-to-address-list address-list=port-scanners address-list-timeout=4w chain=detect-port-scan comment="NULL scan" protocol=tcp tcp-flags=!fin,!syn,!rst,!psh,!ack,!urg
add action=jump chain=detect-port-scan jump-target=drop comment="Drop port scanners" src-address-list=port-scanners
add action=accept chain=detect-ping-flood comment="0:0 and limit for 5 pac/s" disabled=no icmp-options=0:0-255 limit=5,5 protocol=icmp
add action=accept chain=detect-ping-flood comment="3:3 and limit for 5 pac/s" disabled=no icmp-options=3:3 limit=5,5 protocol=icmp
add action=accept chain=detect-ping-flood comment="3:4 and limit for 5 pac/s" disabled=no icmp-options=3:4 limit=5,5 protocol=icmp
add action=accept chain=detect-ping-flood comment="8:0 and limit for 5 pac/s" disabled=no icmp-options=8:0-255 limit=5,5 protocol=icmp
add action=accept chain=detect-ping-flood comment="11:0 and limit for 5 pac/s" disabled=no icmp-options=11:0-255 limit=5,5 protocol=icmp
add action=drop chain=detect-ping-flood comment="drop everything else" disabled=no protocol=icmp
add action=drop chain=detect-virus comment="Drop Blaster Worm" dst-port=135-139 protocol=tcp
add action=drop chain=detect-virus comment="Drop Messenger Worm" dst-port=135-139 protocol=udp
add action=drop chain=detect-virus comment="Drop Blaster Worm" dst-port=445 protocol=tcp
add action=drop chain=detect-virus comment="Drop Blaster Worm" dst-port=445 protocol=udp
add action=drop chain=detect-virus comment=________ dst-port=593 protocol=tcp
add action=drop chain=detect-virus comment=________ dst-port=1024-1030 protocol=tcp
add action=drop chain=detect-virus comment="Drop MyDoom" dst-port=1080 protocol=tcp
add action=drop chain=detect-virus comment=________ dst-port=1214 protocol=tcp
add action=drop chain=detect-virus comment="ndm requester" dst-port=1363 protocol=tcp
add action=drop chain=detect-virus comment="ndm server" dst-port=1364 protocol=tcp
add action=drop chain=detect-virus comment="screen cast" dst-port=1368 protocol=tcp
add action=drop chain=detect-virus comment=hromgrafx dst-port=1373 protocol=tcp
add action=drop chain=detect-virus comment=cichlid dst-port=1377 protocol=tcp
add action=drop chain=detect-virus comment="Beagle detect-virus" dst-port=2745 protocol=tcp
add action=drop chain=detect-virus comment="Drop Dumaru.Y" dst-port=2283 protocol=tcp
add action=drop chain=detect-virus comment="Drop Beagle" dst-port=2535 protocol=tcp
add action=drop chain=detect-virus comment="Drop Beagle.C-K" dst-port=2745 protocol=tcp
add action=drop chain=detect-virus comment="Drop MyDoom" dst-port=3127-3128 protocol=tcp
add action=drop chain=detect-virus comment="Drop Backdoor OptixPro" dst-port=3410 protocol=tcp
add action=drop chain=detect-virus comment=Worm dst-port=4444 protocol=tcp
add action=drop chain=detect-virus comment=Worm dst-port=4444 protocol=udp
add action=drop chain=detect-virus comment="Drop Sasser" dst-port=5554 protocol=tcp
add action=drop chain=detect-virus comment="Drop Beagle.B" dst-port=8866 protocol=tcp
add action=drop chain=detect-virus comment="Drop Dabber.A-B" dst-port=9898 protocol=tcp
add action=drop chain=detect-virus comment="Drop Dumaru.Y" dst-port=10000 protocol=tcp
add action=drop chain=detect-virus comment="Drop MyDoom.B" dst-port=10080 protocol=tcp
add action=drop chain=detect-virus comment="Drop NetBus" dst-port=12345 protocol=tcp
add action=drop chain=detect-virus comment="Drop Kuang2" dst-port=17300 protocol=tcp
add action=drop chain=detect-virus comment="Drop SubSeven" dst-port=27374 protocol=tcp
add action=drop chain=detect-virus comment="Drop PhatBot, Agobot, Gaobot" dst-port=65506 protocol=tcp
add action=accept chain=router-services-lan comment="SSH (22/TCP)" disabled=no dst-port=22 protocol=tcp
add action=accept chain=router-services-lan comment="DNS" disabled=no dst-port=53 protocol=udp
add action=accept chain=router-services-lan comment="DNS" disabled=no dst-port=53 protocol=tcp
add action=accept chain=router-services-lan comment="Winbox (8291/TCP)" disabled=no dst-port=8291 protocol=tcp
add action=accept chain=router-services-lan comment="SNMP" disabled=yes dst-port=161 protocol=udp
add action=accept chain=router-services-lan comment="FTP" disabled=no dst-port=21 protocol=tcp
add action=accept chain=router-services-lan comment="TCP" disabled=no dst-port=23 protocol=tcp
add action=accept chain=router-services-lan comment="NTP" disabled=no dst-port=123 protocol=udp
add action=accept chain=router-services-lan comment="Neighbor discovery" disabled=no dst-port=5678 protocol=udp
add action=drop chain=router-services-wan comment="SSH (22/TCP)" disabled=no dst-port=22 protocol=tcp
add action=accept chain=router-services-wan comment="PPTP (1723/TCP)" disabled=no dst-port=1723 protocol=tcp
add action=drop chain=router-services-wan comment="Winbox (8291/TCP)" disabled=no dst-port=8291 protocol=tcp
add action=accept chain=router-services-wan comment="GRE for PPTP" disabled=no protocol=gre
add action=accept chain=web comment="Allow HTTP" disabled=no dst-port=80 protocol=tcp src-address-list=local-addr
add action=accept chain=web comment="Allow HTTPS" disabled=no dst-port=443 protocol=tcp src-address-list=local-addr
add action=accept chain=email comment="Allow SMTP" dst-port=25 protocol=tcp src-address-list=local-addr
add action=accept chain=email comment="Allow POP" disabled=yes dst-port=110 protocol=tcp src-address-list=local-addr
add action=accept chain=email comment="SMTP over SSL" dst-port=465 protocol=tcp src-address-list=local-addr
add action=accept chain=email comment="SMTP over SSL" dst-port=587 protocol=tcp src-address-list=local-addr
add action=accept chain=email comment="Allow IMAP4 over TLS/SSL" dst-port=993 protocol=tcp src-address-list=local-addr
add action=accept chain=email comment="Allow POPS over TLS/SSL" dst-port=995 protocol=tcp src-address-list=local-addr
add action=accept chain=developer-services comment="Allow Github" dst-port=9418 protocol=tcp src-address-list=local-addr
add action=accept chain=developer-services comment="Allow MongoHQ" dst-port=27637 protocol=tcp src-address-list=local-addr
add action=accept chain=developer-services comment="Allow Postgres" dst-port=5432 protocol=tcp src-address-list=local-addr
add action=accept chain=developer-services comment="Allow SSH to RandomIdeas" disabled=yes dst-port=13022 protocol=tcp src-address-list=local-addr
add action=accept chain=developer-services comment="Allow SFTP" dst-port=22 protocol=tcp src-address-list=local-addr
add action=accept chain=developer-services comment="Allow FTP w/ SSL Port Range" dst-port=10000-10500 protocol=tcp src-address-list=local-addr
add action=accept chain=developer-services comment="Allow Lexmark Printer Port" dst-port=9100 protocol=tcp src-address-list=local-addr
add action=accept chain=developer-services comment="Allow FTP" dst-port=21 protocol=tcp src-address-list=local-addr
add action=accept chain=developer-services comment="Allow DNS Benchmarking and Version Self-check" disabled=yes dst-port=53 protocol=udp src-address-list=local-addr
add action=accept chain=developer-services comment="Allow Remote Desktop" dst-port=3389 protocol=tcp src-address-list=local-addr
add action=accept chain=vpn comment="Allow Cisco (ISAKMP/IKE)" dst-port=500 protocol=udp src-address-list=local-addr
add action=accept chain=vpn comment="Allow L2TP" dst-port=1701 protocol=udp src-address-list=local-addr
add action=accept chain=vpn comment="Allow PPTP" dst-port=1723 protocol=tcp src-address-list=local-addr
add action=accept chain=vpn comment="Allow IPSEC" dst-port=4500 protocol=udp src-address-list=local-addr
add action=accept chain=messaging comment="Allow Microsoft Lync" dst-port=5061 protocol=tcp src-address-list=local-addr
add action=accept chain=messaging comment="Allow Google+ Hangout" dst-port=19302-19309 protocol=udp src-address-list=local-addr
add action=accept chain=messaging comment="Allow Google+ Hangout" dst-port=19305-19309 protocol=tcp src-address-list=local-addr
add action=accept chain=messaging comment="Allow AOL/AIM Instant Messaging" dst-port=5190 protocol=tcp src-address-list=local-addr
add action=accept chain=messaging comment="Allow IIRC Instant Messaging" dst-port=843 protocol=tcp src-address-list=local-addr
add action=accept chain=messaging comment="Allow IIRC Instant Messaging" dst-port=6667 protocol=tcp src-address-list=local-addr
add action=accept chain=messaging comment="Allow Skype" protocol=udp src-address-list=local-addr src-port=61575
add action=accept chain=messaging comment="Allow Google Talk/Jabber" dst-port=5222 protocol=tcp src-address-list=local-addr
add action=accept chain=messaging comment="Allow FaceTime/iMessage" dst-port=3478-3497 protocol=udp src-address-list=local-addr
add action=accept chain=messaging comment="Allow FaceTime/iMessage" dst-port=5223 protocol=tcp src-address-list=local-addr
add action=accept chain=messaging comment="Allow FaceTime/iMessage" dst-port=16384-16387 protocol=udp src-address-list=local-addr
add action=accept chain=messaging comment="Allow FaceTime/iMessage" dst-port=16393-16402 protocol=udp src-address-list=local-addr
add action=accept chain=gaming comment="Allow XBOX Live" dst-port=88 protocol=udp src-address-list=game-console-addr
add action=accept chain=gaming comment="Allow XBOX Live" dst-port=500 protocol=udp src-address-list=game-console-addr
add action=accept chain=gaming comment="Allow XBOX Live" dst-port=3544 protocol=udp src-address-list=game-console-addr
add action=accept chain=gaming comment="Allow XBOX Live" dst-port=4500 protocol=udp src-address-list=game-console-addr
add action=accept chain=gaming comment="Allow XBOX Live" dst-port=3074 protocol=udp src-address-list=game-console-addr
add action=accept chain=gaming comment="Allow XBOX Live" dst-port=3074 protocol=tcp src-address-list=game-console-addr
add action=accept chain=gaming comment="Allow Minecraft" dst-port=25565 protocol=tcp src-address-list=local-addr
add action=accept chain=gaming comment="Allow Steam - game traffic" dst-port=27000-27015 protocol=udp src-address-list=local-addr
add action=accept chain=gaming comment="Allow Steam - matchmaking and HLTV" dst-port=27015-27030 protocol=udp src-address-list=local-addr
add action=accept chain=gaming comment="Allow Steam - downloads" dst-port=27014-27050 protocol=tcp src-address-list=local-addr
add action=accept chain=gaming comment="Allow Steam - voice chat" dst-port=3478 protocol=udp src-address-list=local-addr
add action=accept chain=gaming comment="Allow Steam - voice chat" dst-port=4379-4380 protocol=udp src-address-list=local-addr
add action=accept chain=gaming comment="Allow Mojang - Scrolls" dst-port=8081-8082 protocol=tcp src-address-list=local-addr
add action=accept chain=gaming comment="Allow Battlefield 4" dst-port=9988 protocol=tcp src-address-list=game-console-addr
add action=accept chain=gaming comment="Allow Battlefield 4" dst-port=10901-10999 protocol=tcp src-address-list=game-console-addr
add action=accept chain=gaming comment="Allow Battlefield 4" dst-port=11030-11301 protocol=tcp src-address-list=game-console-addr
add action=accept chain=gaming comment="Allow Battlefield 4" dst-port=11302-11399 protocol=tcp src-address-list=game-console-addr
add action=accept chain=gaming comment="Allow Battlefield 4" dst-port=11001-11029 protocol=tcp src-address-list=game-console-addr
add action=accept chain=gaming comment="Allow Battlefield 4" dst-port=17497 protocol=udp src-address-list=game-console-addr
add action=accept chain=gaming comment="Allow Battlefield 4" dst-port=17503 protocol=tcp src-address-list=game-console-addr
add action=accept chain=gaming comment="Allow Battlefield 4" dst-port=30018 protocol=udp src-address-list=game-console-addr
add action=accept chain=gaming comment="Allow Battlefield 4" dst-port=42130 protocol=tcp src-address-list=game-console-addr
add action=accept chain=gaming comment="Allow Destiny" dst-port=1200 protocol=udp src-address-list=game-console-addr
add action=accept chain=gaming comment="Allow Destiny" dst-port=1001 protocol=udp src-address-list=game-console-addr
add action=accept chain=gaming comment="Allow TitanFall" dst-port=30000-30009 protocol=udp src-address-list=game-console-addr
add action=accept chain=gaming comment="Allow Clash of Clans" dst-port=9339 protocol=tcp src-address-list=local-addr
add action=accept chain=gaming comment="Allow Starcraft - Game client traffic" dst-port=1119-1120 protocol=tcp src-address-list=local-addr
add action=accept chain=gaming comment="Allow Starcraft - Game chat" dst-port=1119 protocol=udp src-address-list=local-addr
add action=accept chain=gaming comment="Allow Starcraft - Blizzard Downloader" dst-port=3724 protocol=tcp src-address-list=local-addr
add action=accept chain=gaming comment="Allow Starcraft - Blizzard Downloader" dst-port=6112-6114 protocol=udp src-address-list=local-addr
add action=accept chain=gaming comment="Allow Starcraft - Blizzard Downloader" dst-port=4000 protocol=tcp src-address-list=local-addr
add action=accept chain=gaming comment="Allow Starcraft - Blizzard Downloader" dst-port=6112-6114 protocol=tcp src-address-list=local-addr;


#-------------------------------------------------------------------------------
#
# Harden Router
#
#-------------------------------------------------------------------------------

# Disable Discover Interfaces
:log info "Disabling neighbor discovery.";
/ip neighbors discovery disable [find];

# Disable bandwidth test server
:log info "Disabling bandwidth test server.";
/tool bandwidth-server set enabled=no;

# Disable Services
:log info "Disabling router services.";
/ip service set telnet disabled=no;
/ip service set ftp disabled=yes;
/ip service set www disabled=yes;
/ip service set ssh port=25000;
/ip service set api disabled=yes;
/ip service set api-ssl disabled=yes;

# Disable Firewall Service Ports
:log info "Disabling firewall service ports.";
/ip firewall service-port set ftp disabled=yes;
/ip firewall service-port set tftp disabled=yes;
/ip firewall service-port set h323 disabled=yes;

# Disable mac server tools
:log info "Disabling mac tools";
/tool mac-server set [ find default=yes ] disabled=yes;
/tool mac-server add interface=$ether2Interface;
/tool mac-server add interface=$ether3Interface;
/tool mac-server add interface=$ether4Interface;
/tool mac-server add interface=$ether5Interface;
/tool mac-server mac-winbox set [ find default=yes ] disabled=yes;
/tool mac-server mac-winbox add interface=$ether2Interface;
/tool mac-server mac-winbox add interface=$ether3Interface;
/tool mac-server mac-winbox add interface=$ether4Interface;
/tool mac-server mac-winbox add interface=$ether5Interface;

#-------------------------------------------------------------------------------
#
# Finish and Cleanup
#
#-------------------------------------------------------------------------------
:log info "Router configuration completed.";
:put "";
:put "Router configuration completed. Please check the system log.";
:put "";

/system reboot;
