#-------------------------------------------------------------------------------
#
# The purpose of this script is to create a standard SOHO type
# configuration for the RB751U which can be built on by the user.
#
#-------------------------------------------------------------------------------

# Set the name of the router
:local systemIdentity "MyMikroTikRouter";

# Secure your RouterOS! Set the password you would like to use when logging on as 'admin'.
:local adminPassword "Password";

# Time Servers (NTP)
:local ntpA "128.138.140.44";
:local ntpB "128.138.141.172";

# Name Servers (DNS) - set to OpenDNS. This should be set to a set of servers that are local and FAST 
:local nsA "208.67.222.222";
:local nsB "208.67.220.220";

# NAT (true/false) - Set to '1' unless you know what you are doing!
:local natEnabled 1;

# Wireless - Automatically set if package is installed 
:local wirelessEnabled 0;
:local wlanFrequency "2412";
:local wlanSSID "MySSID";
:local wlanKey "MySecretKey";
:local wlanInterface "wlan1";

# DHCP - Automatically set if package is installed
:local dhcpEnabled 0;
:local poolStart "192.168.89.11";
:local poolEnd "192.168.89.254";

:local lanAddress "192.168.89.1";
:local lanNetworkAddress "192.168.89.0";
:local lanNetworkBits "24";


# Interfaces
:local ether1Interface "ether1-gateway";
:local ether2Interface "ether2-master-local";
:local ether3Interface "ether3-slave-local";
:local ether4Interface "ether4-slave-local";
:local ether5Interface "ether5-slave-local";

# Timezone
:local timeZone "America/Chicago";

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
/ip firewall address-list remove [find];
/ip firewall nat remove [find];
/ip firewall filter remove [find];

# Check for the required packages
:if ([:len [/system package find name="dhcp" !disabled]] != 0) do={
  :log info "DHCP package found. Enabling DHCP server on router.";
	:set dhcpEnabled 1;
}
:if ([:len [/system package find name="wireless" !disabled]] != 0) do={
  :log info "Wireless package found. Enabling wireless on router.";
	:set wirelessEnabled 1;
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
# Setting the ethernet and wireless interfaces
# Ethernet Port 1 is used as the WAN port and is designated the gateway to DSL/Cable Modem
# DHCP client and masquerde is enabled on ether1
# Ethernet port 2 is used as the switch master for the remain three ports
# ether2 is bridged to wireless lan
#
#-------------------------------------------------------------------------------

# Set up the wireless interface
:log info "Setting wireless LAN interface and security.";
:if ( $wirelessEnabled = 1 ) do={
  /interface wireless reset-configuration [/interface wireless find];
  /interface wireless security-profiles remove [find name!=default];
  /interface wireless security-profiles add name="soho" mode=dynamic-keys authentication-types=wpa-psk,wpa2-psk group-ciphers=aes-ccm wpa-pre-shared-key="$wlanKey" wpa2-pre-shared-key="$wlanKey";
  /interface wireless set $wlanInterface band=2ghz-b/g/n disabled=no frequency=$wlanFrequency mode=ap-bridge security-profile=soho ssid=$wlanSSID country=no_country_set hide-ssid=no ht-txchains=0,1 ht-rxchains=0,1 wireless-protocol=any;
}


# Setup the wired interface(s)
/interface set ether1 name="$ether1Interface";

:if ( $dhcpEnabled = 1 ) do={
  :log info "Setting up a dhcp client on the gateway interface";
  /ip dhcp-client add interface=$ether1Interface disabled=no comment="Gateway interface. Connect to ISP Modem" use-peer-dns=no use-peer-ntp=no add-default-route=no;
}

/interface ethernet {
  set ether2 name="$ether2Interface";
  set ether3 name="$ether3Interface" master-port=$ether2Interface;
  set ether4 name="$ether4Interface" master-port=$ether2Interface;
  set ether5 name="$ether5Interface" master-port=$ether2Interface;
}

# Setup the bridge
:log info "Configuring bridge on ether2 and wlan.";
/interface bridge add name=bridge-local disabled=no auto-mac=no protocol-mode=rstp;
/interface bridge set "bridge-local" admin-mac=[/interface ethernet get $ether2Interface mac-address];

/interface bridge {
  port add bridge=bridge-local disabled=no edge=auto external-fdb=auto horizon=none interface=ether2-master-local path-cost=10 point-to-point=auto priority=0x80;
  port add bridge=bridge-local disabled=no edge=auto external-fdb=auto horizon=none interface=wlan1 path-cost=10 point-to-point=auto priority=0x80;
}

#-------------------------------------------------------------------------------
#
# DHCP Server
# configure the server on the bridge interface for handing out ip to both
# lan and wlan. Address pool is defined above with $poolStart and $poolEnd.
#
#-------------------------------------------------------------------------------

:log info "Setting LAN address to $lanAddress/$lanNetworkBits on the bridge interface.";
/ip address add address="$lanAddress/$lanNetworkBits" interface=bridge-local comment="";

:log info "Setting DNS servers to $nsA and $nsB.";
/ip dns set allow-remote-requests=yes servers="$nsA,$nsB";

:if ( $dhcpEnabled = 1 ) do={
  :log info "Setting DHCP server on bridge interface, pool $poolStart-$poolEnd";
  /ip pool add name="local-dhcp-pool" ranges="$poolStart-$poolEnd";
  /ip dhcp-server add name="dhcp-server" address-pool="local-dhcp-pool" interface=bridge-local disabled=no;
  /ip dhcp-server network add address="$lanNetworkAddress/$lanNetworkBits" gateway=$lanAddress dns-server=$lanAddress comment="DHCP for local network";
}

#-------------------------------------------------------------------------------
#
# Firewall
#
#-------------------------------------------------------------------------------

# Set up NAT
:log info "NATing to interface $ether1Interface";
/ip firewall nat add action=masquerade chain=srcnat comment="NAT" disabled=no out-interface="$ether1Interface";

# Disable Discover Interfaces
/ip neighbors discovery disable [find];

# Enable firewall filter on bridged ports
/interface bridge settings set use-ip-firewall=yes;

# Disable bandwidth test server
/tool bandwidth-server set enabled=no;

#
:log info "Router configuration completed.";
:put "";
:put "Router configuration completed. Please check the system log.";
:put "";

/system reboot;
