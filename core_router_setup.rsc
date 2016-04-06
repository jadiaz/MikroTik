{
    #-------------------------------------------------------------------------------
    #
    # The purpose of this script is to create a standard SOHO type
    # configuration for ROS which can be built on by the user.
    #
    #-------------------------------------------------------------------------------
    # Set the name of the router
    :local systemName "MyRouter"

    # Secure your RouterOS! Set the password you would like to use when logging on as 'admin'.
    :local adminPassword "test"

    # Time Servers (NTP)
    :local ntpA "173.230.149.23"
    :local ntpB "198.110.48.12"

    # Name Servers (DNS) - set to OpenDNS. This should be set to a set of servers that are local and FAST 
    :local nsA "216.116.96.2"
    :local nsB "216.52.254.33"
    :local nsC "68.111.16.30"

    # DHCP - Automatically set if package is installed
    :local dhcpServer "dhcp-server"
    :local lanPoolName ""
    :local poolStart "192.168.50.1"
    :local poolEnd "192.168.50.100"

    :local lanAddress "192.168.50.1"
    :local lanNetworkAddress "192.168.50.0"
    :local lanNetworkBits "24"

    # Interfaces
    :local ether1 "ether1-gateway"
    :local ether2 "ether2-master-local"
    :local ether3 "ether3-slave-local"
    :local ether4 "ether4-slave-local"
    :local ether5 "ether5-slave-local"

    # SSH
    :local sshPort 22

    #-------------------------------------------------------------------------------
    #
    # Configuration
    #
    #-------------------------------------------------------------------------------
    :log info "--- Setting timezone ---";
    /system clock set time-zone-autodetect=yes

    :log info "--- Setting up the time server client ---";
    /system ntp client set enabled=yes primary-ntp=$ntpA secondary-ntp=$ntpB

    :log info "--- Setting the system name ---";
    /system identity set name=$systemName;

    :log info "--- Setting the admin password ---";
    /user set admin password=$adminPassword;

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

    :log info "--- Resetting Mac Server ---";
    /tool mac-server remove [find interface!=all]
    /tool mac-server set [find] disabled=no
    /tool mac-server mac-winbox remove [find interface!=all]
    /tool mac-server mac-winbox set [find] disabled=no

    :log info "--- Resetting neighbor discovery ---";
    /ip neighbor discovery set [find name=$ether1] discover=yes

    #-------------------------------------------------------------------------------
    #
    # Setting the ethernet interfaces
    # Ethernet Port 1 is used as the WAN port and is designated the gateway to DSL/Cable Modem
    # DHCP client and masquerde is enabled on ether1
    # Ethernet port 2 is used as the switch master for the remain three ports
    #
    #-------------------------------------------------------------------------------

    :log info "--- Reset interfaces to default ---";
    :foreach iface in=[/interface ethernet find] do={
      /interface ethernet set $iface name=[get $iface default-name]
      /interface ethernet set $iface master-port=none
    }

    :log info "--- Remove old DHCP client ---";
    :local o [/ip dhcp-client find]
    :if ([:len $o] != 0) do={ /ip dhcp-client remove $o }

    :log info "--- Setup the wired interface(s) ---";
    /interface set ether1 name="$ether1";

    :log info "--- Setting up a dhcp client on the gateway interface ---";
    /ip dhcp-client add interface=$ether1 disabled=no comment="Gateway Interface. Connect to ISP modem." use-peer-dns=no use-peer-ntp=no add-default-route=no;

    /interface ethernet {
      set ether2 name="$ether2";
      set ether3 name="$ether3" master-port=$ether2;
      set ether4 name="$ether4" master-port=$ether2;
      set ether5 name="$ether5" master-port=$ether2;
    }

    #-------------------------------------------------------------------------------
    #
    # DHCP Server
    # configure the server on the lan interface for handing out ip to both
    # lan and wlan. Address pool is defined above with $poolStart and $poolEnd.
    #
    #-------------------------------------------------------------------------------
    :local o [/ip dhcp-server network find]
    :if ([:len $o] != 0) do={ /ip dhcp-server network remove $o }

    :local o [/ip dhcp-server find]
    :if ([:len $o] != 0) do={ /ip dhcp-server remove $o }

    :local o [/ip pool find]
    :if ([:len $o] != 0) do={ /ip pool remove $o }

    /ip dns {
      set allow-remote-requests=no
      :local o [static find]
      :if ([:len $o] != 0) do={ static remove $o }
    }

    /ip address {
      :local o [find]
      :if ([:len $o] != 0) do={ remove $o }
    }

    :log info "--- Setting the routers LAN address to $lanAddress/$lanNetworkBits ---";
    /ip address add address="$lanAddress/$lanNetworkBits" interface=$ether2 network=$lanNetworkAddress comment="core router LAN address";

    :log info "--- Setting DHCP server on interface, pool $poolStart-$poolEnd ---";
    /ip pool add name=$lanPoolName ranges="$poolStart-$poolEnd";
    /ip dhcp-server add name="$dhcpServer" address-pool=$lanPoolName interface=$ether2 disabled=no lease-time=10m;
    /ip dhcp-server network add address="$lanNetworkAddress/$lanNetworkBits" gateway=$lanAddress dns-server=$lanAddress comment="local DHCP network";

    :log info "--- Setting DNS servers to $nsA and $nsB ---";
    /ip dns set allow-remote-requests=yes servers="$nsA,$nsB,$nsC";


    #-------------------------------------------------------------------------------
    #
    # Firewall
    #
    #-------------------------------------------------------------------------------

    :log info "--- Setting up NAT on WAN interface ---";
    /ip firewall nat add chain=srcnat out-interface=$ether1 action=masquerade

    :log info "--- Setting up simple firewall rules ---";
    /ip firewall {
      filter add chain=input action=accept connection-state=established,related comment="Allow established connections"
      filter add chain=input action=drop in-interface=$ether1
      filter add chain=forward action=fasttrack-connection connection-state=established,related
      filter add chain=forward action=accept connection-state=established,related
      filter add chain=forward action=drop connection-state=invalid
      filter add chain=forward action=drop connection-state=new connection-nat-state=!dstnat in-interface=$ether1
    }
    #-------------------------------------------------------------------------------
    #
    # Harden Router
    #
    #-------------------------------------------------------------------------------
    :log info "--- Disabling neighbor discovery ---";
    /ip neighbor discovery set [find name="ether1-gateway"] discover=no;

    :log info "--- Disabling bandwidth test server ---";
    /tool bandwidth-server set enabled=no;

    :log info "--- Disabling router services ---";
    /ip service {
      :foreach s in=[find where !disabled and name!=telnet and name!=winbox] do={
        set $s disabled=yes;
      }

      :log info "--- Enabling secure shell service on port  ---";
      :local o [find name=ssh !disabled]
      :if ([:len $o] = 0) do={
        set ssh disabled=no port=$sshPort;
      }
    }

    :log info "--- Disabling firewall service ports ---";
    /ip firewall service-port {
      :foreach o in=[find where !disabled and name!=sip and name!=pptp] do={
        set $o disabled=yes;
      }
    }

    :log info "--- Disable mac server tools ---";
    /tool mac-server disable [find];
    /tool mac-server mac-winbox disable [find];

    :log info "Auto configuration ended.";
    :put "";
    :put "Auto configuration ended. Please check the system log.";

    /system reboot;
}