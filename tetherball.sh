#!/bin/sh
# tetherball.sh by Stefan Tomanek <stefan@pico.ruhr.de>
WLAN_SSID="tetherball"
WLAN_CHANNEL="1"
WLAN_PSK="secretstuff"
WLAN_OWN_ADDRESS="10.9.9.1/24"
WLAN_DHCP_RANGE="10.9.9.100,10.9.9.150,255.255.255.0,1h"
WLAN_DEV="wlan0"

### no user servicable parts beyond this line ###
IWCONFIG="iwconfig"
IP="ip"
HOSTAPD="hostapd"
DNSMASQ="dnsmasq"
SYSCTL="sysctl"
IPTABLES="iptables"

AP_CONF="$(mktemp hostapd-${WLAN_DEV}-XXXXX --tmpdir --suffix=.conf)"

cat <<EOF > "$AP_CONF"
interface=$WLAN_DEV
ssid=$WLAN_SSID
hw_mode=g
channel=$WLAN_CHANNEL
wpa=2
wpa_passphrase=$WLAN_PSK
EOF

echo $AP_CONF

$HOSTAPD -d "$AP_CONF" &
HOSTAP_PID=$!
sleep 1

$IP addr add dev $WLAN_DEV "$WLAN_OWN_ADDRESS"
$IP link set $WLAN_DEV up
$SYSCTL net.ipv4.ip_forward=1
$IPTABLES -t nat -A POSTROUTING -s "$WLAN_OWN_ADDRESS" -j MASQUERADE

$DNSMASQ -i wlan0 --dhcp-range="$WLAN_DHCP_RANGE" -d

# cleanup
kill $HOSTAP_PID
rm "$AP_CONF"
$IPTABLES -t nat -D POSTROUTING -s "$WLAN_OWN_ADDRESS" -j MASQUERADE
$IP addr del dev $WLAN_DEV "$WLAN_OWN_ADDRESS"
$IP link set $WLAN_DEV down
