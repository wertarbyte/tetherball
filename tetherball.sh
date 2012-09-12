#!/bin/sh
# tetherball.sh by Stefan Tomanek <stefan@pico.ruhr.de>
WLAN_SSID=""
WLAN_CHANNEL="1"
WLAN_PSK=""
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

# parse command line
while getopts ":i:ws:c:" opt; do
	case $opt in
		i)
			echo "WLAN device set to $OPTARG" >&2
			WLAN_DEV="$OPTARG"
			;;
		w)
			read -sp "WPA passphrase: " WLAN_PSK
			echo "" >&2
			;;
		s)
			echo "SSID set to $OPTARG" >&2
			WLAN_SSID="$OPTARG"
			;;
		c)
			echo "Channel set to $OPTARG" >&2
			WLAN_CHANNEL="$OPTARG"
			;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			exit 1
			;;
		:)
			echo "Option -$OPTARG requires an argument." >&2
			exit 1
			;;
	esac
done

if [ -z "$WLAN_SSID" ]; then
	echo "No ESSID (-s) specified" >&1
	exit 1
fi

AP_CONF="$(mktemp hostapd-${WLAN_DEV}-XXXXX --tmpdir --suffix=.conf)"

{
	cat <<EOF
interface=$WLAN_DEV
ssid=$WLAN_SSID
hw_mode=g
channel=$WLAN_CHANNEL
EOF
	if [ -n "$WLAN_PSK" ]; then
	cat <<EOF
wpa=2
wpa_passphrase=$WLAN_PSK
EOF
	fi
} > "$AP_CONF"

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
