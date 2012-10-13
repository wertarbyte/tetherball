#!/bin/bash
# tetherball.sh by Stefan Tomanek <stefan@pico.ruhr.de>
WLAN_SSID=""
WLAN_CHANNEL="1"
WLAN_PSK=""
WLAN_OWN_ADDRESS="10.9.9.1/24"
WLAN_DHCP_RANGE="10.9.9.100,10.9.9.150,255.255.255.0,1h"
WLAN_DEV=""
WLAN_PHY=""


### no user servicable parts beyond this line ###
IWCONFIG="iwconfig"
IP="ip"
IW="iw"
HOSTAPD="hostapd"
DNSMASQ="dnsmasq"
SYSCTL="sysctl"
IPTABLES="iptables"

cleanup() {
	echo "Cleaning up..." >&2
	# cleanup
	[ -n "$HOSTAP_PID" ] && kill $HOSTAP_PID
	[ -e "$AP_CONF" ]    && rm "$AP_CONF"
	$IPTABLES -t nat -D POSTROUTING -s "$WLAN_OWN_ADDRESS" -j MASQUERADE
	$IP addr del dev $WLAN_DEV "$WLAN_OWN_ADDRESS"
	$IP link set $WLAN_DEV down

	if [ -n "$WLAN_PHY" ]; then
		# tear down the interface
		echo "Taking down the VAP..." >&2
		$IW dev "$WLAN_DEV" del
	fi
}

# parse command line
while getopts ":i:p:ws:c:" opt; do
	case $opt in
		i)
			echo "WLAN device set to $OPTARG" >&2
			WLAN_DEV="$OPTARG"
			;;
		p)
			echo "WLAN physical device set to $OPTARG" >&2
			WLAN_PHY="$OPTARG"
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
	echo "No ESSID (-s) specified" >&2
	exit 1
fi

if [ -n "$WLAN_PHY" ]; then
	# create a new VAP
	WLAN_DEV="tb-${WLAN_SSID// /_}"
	WLAN_DEV="${WLAN_DEV:0:15}"
	$IW phy "$WLAN_PHY" interface add "$WLAN_DEV" type __ap || exit 1
	RND_MAC=$(printf "%02x:%02x:%02x:%02x:%02x:%02x" 0x00 0x16 0x3e $(($RANDOM%0x7F)) $(($RANDOM%0xFF)) $(($RANDOM%0xFF)))
	$IP link set dev "$WLAN_DEV" address "$RND_MAC"
fi

if [ -z "$WLAN_DEV" ]; then
	echo "No WLAN interface or device specified (-i/-p)" >&2
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

trap cleanup EXIT

$HOSTAPD -d "$AP_CONF" &
HOSTAP_PID=$!
sleep 1

$IP addr add dev $WLAN_DEV "$WLAN_OWN_ADDRESS"
$IP link set $WLAN_DEV up
$SYSCTL net.ipv4.ip_forward=1
$IPTABLES -t nat -A POSTROUTING -s "$WLAN_OWN_ADDRESS" -j MASQUERADE

$DNSMASQ -i wlan0 --dhcp-range="$WLAN_DHCP_RANGE" -d
