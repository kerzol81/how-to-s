:global wanInterface ether1_WAN
:global lanInterface bridge1
:global lanAddressSpace 10.0.0.0/24
:global bogonIpList Bogons

# disable services
/ip service disable [find name=telnet]
/ip service disable [find name=ftp]
/ip service disable [find name=www]
/ip service disable [find name=www-ssl]
/ip service disable [find name=api]
/ip service disable [find name=api-ssl]
/tool bandwidth-server set enabled=no
/ip dns set allow-remote-requests=no
/ip socks set enabled=no

# disable romon
/tool romon set enabled=no

# enable strong crypto
/ip ssh set strong-crypto=yes

# create BOGON IP list:

/ip firewall address-list
add address=0.0.0.0/8 list=$bogonIpList
add address=10.0.0.0/8 list=$bogonIpList
add address=100.64.0.0/10 list=$bogonIpList
add address=127.0.0.0/8 list=$bogonIpList
add address=169.254.0.0/16 list=$bogonIpList
add address=172.16.0.0/12 list=$bogonIpList
add address=192.0.0.0/24 list=$bogonIpList
add address=192.0.2.0/24 list=$bogonIpList
add address=192.168.0.0/16 list=$bogonIpList
add address=198.18.0.0/15 list=$bogonIpList
add address=198.51.100.0/24 list=$bogonIpList
add address=203.0.113.0/24 list=$bogonIpList
add address=224.0.0.0/3 list=$bogonIpList

# INPUT

/ip firewall filter
add action=accept chain=input comment="Accept established and related" connection-state=established,related
add action=accept chain=input comment="Accept all connections from local network" in-interface=$lanInterface
add action=accept chain=input comment="Allow WINBOX from LAN" in-interface=$lanInterface
add action=accept chain=input comment="Accept all connections from local network" in-interface=$lanInterface
add action=drop chain=input comment="Drop invalid packets" connection-state=invalid
add action=drop chain=input comment="Drop all packets which are not destined to routes IP address" dst-address-type=!local
add action=drop chain=input comment="Drop all packets which does not have unicast source IP address" src-address-type=!unicast
add action=drop chain=input comment="Drop Bogons" in-interface=$wanInterface src-address-list=$bogonIpList
add action=drop chain=input in-interface=$wanInterface log=yes log-prefix="input drop" 

# FORWARD

/ip firewall filter
add chain=forward comment="fasttrack" action=fasttrack-connection connection-state=established,related
add chain=forward comment="Accept established and related packets" connection-state=established,related
add action=drop chain=forward comment="Drop all packets from local network to internet which should not exist in public network" dst-address-list=Bogons in-interface=$wanInterface
