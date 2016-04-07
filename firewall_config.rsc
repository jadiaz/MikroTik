{
    #-------------------------------------------------------------------------------
    #
    # Firewall Configuration
    #
    #-------------------------------------------------------------------------------
    :log info "--- Starting firewall configuration ---";

    :local lanNetworkAddress ""
    :local lanNetworkBits "24"

    :log info "--- Clearing all pre-existing settings ---";
    /ip firewall {
      :log info "--- Clearing any existing NATs ---";
      :local o [nat find]
      :if ([:len $o] != 0) do={ nat remove numbers=$o }

      :log info "--- Clearing old filters ---";
      :local o [filter find where dynamic=no]
      :if ([:len $o] != 0) do={ filter remove $o }

      :log info "--- Clearing old address lists ---";
      :local o [address-list find]
      :if ([:len $o] != 0) do={ address-list remove numbers=$o }

      :log info "--- Clearing previous mangles ---";
      :local o [mangle find where dynamic=no]
      :if ([:len $o] != 0) do={ mangle remove numbers=$o }

      :log info "--- Clearing previous layer-7 ---";
      :local o [layer7-protocol find]
      :if ([:len $o] != 0) do={ layer7-protocol remove numbers=$o }
    }

    :log info "--- Adding $lanNetworkAddress/$lanNetworkBits to local address list ---";
    /ip firewall address-list add list=local-addr address="$lanNetworkAddress/$lanNetworkBits";

    :log info "--- Adding bogon addresses to list ---";
    /ip firewall address-list {
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
      add list="bogon-addr" address=224.0.0.0/3
    }

    :log info "--- Adding filter set ---";
    /ip firewall filter {
        add chain=input comment="Allow established connections" connection-state=established,related
        add action=jump chain=input comment="Check for dns recursion" in-interface=ether1-gateway jump-target=detect-dns-recursion
        add action=jump chain=input comment="Check for port scanning" jump-target=detect-port-scan
        add action=jump chain=input comment="Check for ping flooding" jump-target=detect-ping-flood protocol=icmp
        add action=jump chain=input comment="Drop inbound to invalid address" dst-address-type=!local jump-target=drop
        add action=jump chain=input comment="Allow router services on the wan" in-interface=ether1-gateway jump-target=router-services-wan
        add action=jump chain=input comment="Allow router services on the lan" in-interface=ether2-master-local jump-target=router-services-lan
        add action=drop chain=input comment="Drop everything else on the input" in-interface=ether1-gateway
        add action=fasttrack-connection chain=forward connection-state=established,related
        add chain=forward connection-state=established,related
        add action=drop chain=forward connection-state=invalid comment="Drop invalid connections"
        add action=drop chain=forward connection-nat-state=!dstnat connection-state=new in-interface=ether1-gateway comment="Drop connections that are not originating on LAN"
        add action=jump chain=forward comment="Check for infected computers" jump-target=detect-virus
        add action=jump chain=forward comment="Allow gaming services" jump-target=gaming
        add action=jump chain=forward comment="Allow web traffic" jump-target=web
        add action=jump chain=forward comment="Allow email" jump-target=email
        add action=jump chain=forward comment="Allow outgoing VPN connections" jump-target=vpn
        add action=jump chain=forward comment="Allow development" jump-target=developer-services
        add action=jump chain=forward comment="Allow messaging" jump-target=messaging
        add action=log chain=forward log-prefix="[ No Match ]"
        add action=drop chain=drop log-prefix="[ Final Drop ]"
        add action=jump chain=detect-dns-recursion comment="Deny requests for DNS from internet" dst-port=53 jump-target=drop protocol=tcp
        add action=jump chain=detect-dns-recursion comment="Deny requests for DNS from internet" dst-port=53 jump-target=drop protocol=udp
        add action=add-src-to-address-list address-list=port-scanners address-list-timeout=4w chain=detect-port-scan protocol=tcp psd=21,3s,3,1
        add action=add-src-to-address-list address-list=port-scanners address-list-timeout=4w chain=detect-port-scan comment="NMAP FIN Stealth scan" protocol=tcp tcp-flags=fin,!syn,!rst,!psh,!ack,!urg
        add action=add-src-to-address-list address-list=port-scanners address-list-timeout=4w chain=detect-port-scan comment="SYN/FIN scan" protocol=tcp tcp-flags=fin,syn
        add action=add-src-to-address-list address-list=port-scanners address-list-timeout=4w chain=detect-port-scan comment="SYN/RST scan" protocol=tcp tcp-flags=syn,rst
        add action=add-src-to-address-list address-list=port-scanners address-list-timeout=4w chain=detect-port-scan comment="TCP Xmas scan" protocol=tcp tcp-flags=fin,psh,urg,!syn,!rst,!ack
        add action=add-src-to-address-list address-list=port-scanners address-list-timeout=4w chain=detect-port-scan comment="NULL scan" protocol=tcp tcp-flags=!fin,!syn,!rst,!psh,!ack,!urg
        add action=jump chain=detect-port-scan comment="Drop port scanners" jump-target=drop src-address-list=port-scanners
        add chain=detect-ping-flood comment="0:0 and limit for 5 pac/s" icmp-options=0 limit=5,5:packet protocol=icmp
        add chain=detect-ping-flood comment="3:3 and limit for 5 pac/s" icmp-options=3:3 limit=5,5:packet protocol=icmp
        add chain=detect-ping-flood comment="3:4 and limit for 5 pac/s" icmp-options=3:4 limit=5,5:packet protocol=icmp
        add chain=detect-ping-flood comment="8:0 and limit for 5 pac/s" icmp-options=8 limit=5,5:packet protocol=icmp
        add chain=detect-ping-flood comment="11:0 and limit for 5 pac/s" icmp-options=11 limit=5,5:packet protocol=icmp
        add action=drop chain=detect-ping-flood comment="drop everything else" protocol=icmp
        add action=drop chain=detect-virus comment="Drop Blaster Worm" dst-port=135-139 protocol=tcp
        add action=drop chain=detect-virus comment="Drop Messenger Worm" dst-port=135-139 log-prefix="[ detect-virus ]" protocol=udp
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
        add chain=router-services-lan comment="SSH (22/TCP)" dst-port=22 protocol=tcp
        add chain=router-services-lan comment=DNS dst-port=53 protocol=udp
        add chain=router-services-lan comment=DNS dst-port=53 protocol=tcp
        add chain=router-services-lan comment="Winbox (8291/TCP)" dst-port=8291 protocol=tcp
        add chain=router-services-lan comment=SNMP disabled=yes dst-port=161 protocol=udp
        add chain=router-services-lan comment=FTP dst-port=21 protocol=tcp
        add chain=router-services-lan comment=TCP dst-port=23 protocol=tcp
        add chain=router-services-lan comment=NTP dst-port=123 protocol=udp
        add chain=router-services-lan comment="Neighbor discovery" dst-port=5678 protocol=udp
        add action=drop chain=router-services-wan comment="SSH (22/TCP)" dst-port=22 protocol=tcp
        add chain=router-services-wan comment="PPTP (1723/TCP)" dst-port=1723 protocol=tcp
        add action=drop chain=router-services-wan comment="Winbox (8291/TCP)" dst-port=8291 protocol=tcp
        add chain=router-services-wan comment="GRE for PPTP" protocol=gre
        add chain=web comment="Allow HTTP" dst-port=80 protocol=tcp src-address-list=local-addr
        add chain=web comment="Allow HTTPS" dst-port=443 protocol=tcp src-address-list=local-addr
        add chain=email comment="Allow SMTP" dst-port=25 protocol=tcp src-address-list=local-addr
        add chain=email comment="Allow POP" disabled=yes dst-port=110 protocol=tcp src-address-list=local-addr
        add chain=email comment="SMTP over SSL" dst-port=465 protocol=tcp src-address-list=local-addr
        add chain=email comment="SMTP over SSL" dst-port=587 protocol=tcp src-address-list=local-addr
        add chain=email comment="Allow IMAP4 over TLS/SSL" dst-port=993 protocol=tcp src-address-list=local-addr
        add chain=email comment="Allow POPS over TLS/SSL" dst-port=995 protocol=tcp src-address-list=local-addr
        add chain=developer-services comment="Allow Github" dst-port=9418 protocol=tcp src-address-list=local-addr
        add chain=developer-services comment="Allow MongoHQ" dst-port=27637 protocol=tcp src-address-list=local-addr
        add chain=developer-services comment="Allow Postgres" dst-port=5432 protocol=tcp src-address-list=local-addr
        add chain=developer-services comment="Allow SFTP" dst-port=22 protocol=tcp src-address-list=local-addr
        add chain=developer-services comment="Allow FTP w/ SSL Port Range" dst-port=10000-10500 protocol=tcp src-address-list=local-addr
        add chain=developer-services comment="Allow FTP" dst-port=21 protocol=tcp src-address-list=local-addr
        add chain=developer-services comment="Allow DNS Benchmarking and Version Self-check" dst-port=53 protocol=udp src-address-list=local-addr
        add chain=developer-services comment="Allow Remote Desktop" dst-port=3389 protocol=tcp src-address-list=local-addr
        add chain=vpn comment="Allow Cisco (ISAKMP/IKE)" dst-port=500 protocol=udp src-address-list=local-addr
        add chain=vpn comment="Allow L2TP" dst-port=1701 protocol=udp src-address-list=local-addr
        add chain=vpn comment="Allow PPTP" dst-port=1723 protocol=tcp src-address-list=local-addr
        add chain=vpn comment="Allow IPSEC" dst-port=4500 protocol=udp src-address-list=local-addr
        add chain=messaging comment="Allow Microsoft Lync" dst-port=5061 protocol=tcp src-address-list=local-addr
        add chain=messaging comment="Allow Google+ Hangout" dst-port=19302-19309 protocol=udp src-address-list=local-addr
        add chain=messaging comment="Allow Google+ Hangout" dst-port=19305-19309 protocol=tcp src-address-list=local-addr
        add chain=messaging comment="Allow AOL/AIM Instant Messaging" dst-port=5190 protocol=tcp src-address-list=local-addr
        add chain=messaging comment="Allow IIRC Instant Messaging" dst-port=843 protocol=tcp src-address-list=local-addr
        add chain=messaging comment="Allow IIRC Instant Messaging" dst-port=6667 protocol=tcp src-address-list=local-addr
        add chain=messaging comment="Allow Skype" protocol=udp src-address-list=local-addr src-port=61575
        add chain=messaging comment="Allow Google Talk/Jabber" dst-port=5222 protocol=tcp src-address-list=local-addr
        add chain=messaging comment="Allow FaceTime/iMessage" dst-port=3478-3497 protocol=udp src-address-list=local-addr
        add chain=messaging comment="Allow FaceTime/iMessage" dst-port=5223 protocol=tcp src-address-list=local-addr
        add chain=messaging comment="Allow FaceTime/iMessage" dst-port=16384-16387 protocol=udp src-address-list=local-addr
        add chain=messaging comment="Allow FaceTime/iMessage" dst-port=16393-16402 protocol=udp src-address-list=local-addr
        add chain=gaming comment="Allow XBOX Live" dst-port=88 protocol=udp src-address-list=game-console-addr
        add chain=gaming comment="Allow XBOX Live" dst-port=500 protocol=udp src-address-list=game-console-addr
        add chain=gaming comment="Allow XBOX Live" dst-port=3544 protocol=udp src-address-list=game-console-addr
        add chain=gaming comment="Allow XBOX Live" dst-port=4500 protocol=udp src-address-list=game-console-addr
        add chain=gaming comment="Allow XBOX Live" dst-port=3074 protocol=udp src-address-list=game-console-addr
        add chain=gaming comment="Allow XBOX Live" dst-port=3074 protocol=tcp src-address-list=game-console-addr
        add chain=gaming comment="Allow Minecraft" dst-port=25565 protocol=tcp src-address-list=local-addr
        add chain=gaming comment="Allow Steam - game traffic" dst-port=27000-27015 protocol=udp src-address-list=local-addr
        add chain=gaming comment="Allow Steam - matchmaking and HLTV" dst-port=27015-27030 protocol=udp src-address-list=local-addr
        add chain=gaming comment="Allow Steam - downloads" dst-port=27014-27050 protocol=tcp src-address-list=local-addr
        add chain=gaming comment="Allow Steam - voice chat" dst-port=3478 protocol=udp src-address-list=local-addr
        add chain=gaming comment="Allow Steam - voice chat" dst-port=4379-4380 protocol=udp src-address-list=local-addr
        add chain=gaming comment="Allow Battlefield 4" dst-port=9988 protocol=tcp src-address-list=game-console-addr
        add chain=gaming comment="Allow Battlefield 4" dst-port=10901-10999 protocol=tcp src-address-list=game-console-addr
        add chain=gaming comment="Allow Battlefield 4" dst-port=11030-11301 protocol=tcp src-address-list=game-console-addr
        add chain=gaming comment="Allow Battlefield 4" dst-port=11302-11399 protocol=tcp src-address-list=game-console-addr
        add chain=gaming comment="Allow Battlefield 4" dst-port=11001-11029 protocol=tcp src-address-list=game-console-addr
        add chain=gaming comment="Allow Battlefield 4" dst-port=17497 protocol=udp src-address-list=game-console-addr
        add chain=gaming comment="Allow Battlefield 4" dst-port=17503 protocol=tcp src-address-list=game-console-addr
        add chain=gaming comment="Allow Battlefield 4" dst-port=30018 protocol=udp src-address-list=game-console-addr
        add chain=gaming comment="Allow Battlefield 4" dst-port=42130 protocol=tcp src-address-list=game-console-addr
        add chain=gaming comment="Allow Destiny" dst-port=1200 protocol=udp src-address-list=game-console-addr
        add chain=gaming comment="Allow Destiny" dst-port=1001 protocol=udp src-address-list=game-console-addr
        add chain=gaming comment="Allow TitanFall" dst-port=30000-30009 protocol=udp src-address-list=game-console-addr
        add chain=gaming comment="Allow Starcraft - Game client traffic" dst-port=1119-1120 protocol=tcp src-address-list=local-addr
        add chain=gaming comment="Allow Starcraft - Game chat" dst-port=1119 protocol=udp src-address-list=local-addr
        add chain=gaming comment="Allow Starcraft - Blizzard Downloader" dst-port=3724 protocol=tcp src-address-list=local-addr
        add chain=gaming comment="Allow Starcraft - Blizzard Downloader" dst-port=6112-6114 protocol=udp src-address-list=local-addr
        add chain=gaming comment="Allow Starcraft - Blizzard Downloader" dst-port=4000 protocol=tcp src-address-list=local-addr
        add chain=gaming comment="Allow Starcraft - Blizzard Downloader" dst-port=6112-6114 protocol=tcp src-address-list=local-addr
    }
    :log info "--- Finished configuring firewall ---";
}