#!/bin/bash
# tetherball.sh by Stefan Tomanek <stefan@pico.ruhr.de>
WLAN_SSID=""
WLAN_CHANNEL=""
WLAN_DEFAULT_CHANNEL="1"
WLAN_PSK=""
WLAN_OWN_ADDRESS="10.9.9.1/24"
WLAN_DHCP_RANGE="10.9.9.100,10.9.9.150,255.255.255.0,1h"
WLAN_BRIDGE=""
WLAN_DEV=""
WLAN_PHY=""


### no user servicable parts beyond this line ###
IWCONFIG="iwconfig"
IP="ip"
IW="iw"
IWLIST="iwlist"
HOSTAPD="hostapd"
DNSMASQ="dnsmasq"
SYSCTL="sysctl"
IPTABLES="iptables"
BRCTL="brctl"

cleanup() {
	echo "Cleaning up..." >&2
	# cleanup
	[ -n "$HOSTAP_PID" ] && kill $HOSTAP_PID
	[ -e "$AP_CONF" ]    && rm "$AP_CONF"
	if [ -z "$WLAN_BRIDGE" ]; then
		$IPTABLES -t nat -D POSTROUTING -s "$WLAN_OWN_ADDRESS" -j MASQUERADE
		$IP addr del dev $WLAN_DEV "$WLAN_OWN_ADDRESS"
		$IP link set $WLAN_DEV down
	else
		$BRCTL delif "$WLAN_BRIDGE" "$WLAN_DEV"
	fi

	if [ -n "$WLAN_PHY" ]; then
		# tear down the interface
		echo "Taking down the VAP..." >&2
		$IW dev "$WLAN_DEV" del
	fi
}

usage() {
	echo "tetherball.sh by Stefan Tomanek <stefan@pico.ruhr.de>"
	echo ""
	echo " -f <file>         Read configuration file"
	echo " -i <interface>    WLAN interface to use"
	echo " -p <phys>         Physical interface to use (dynamically create VAP)"
	echo " -b <bridge>       Do not launch DHCP server, but add interface to bridge"
	echo " -s <ESSID>        ESSID to use for the network"
	echo " -c <channel>      Channel to use for the network"
	echo " -w                Use WPA preshared key (read from stdin)"
}

# parse command line
while getopts ":i:b:p:ws:c:f:" opt; do
	case $opt in
		i)
			echo "WLAN device set to $OPTARG" >&2
			CMD_WLAN_DEV="$OPTARG"
			;;
		p)
			echo "WLAN physical device set to $OPTARG" >&2
			CMD_WLAN_PHY="$OPTARG"
			;;
		w)
			read -sp "WPA passphrase: " CMD_WLAN_PSK
			echo "" >&2
			;;
		s)
			echo "SSID set to $OPTARG" >&2
			CMD_WLAN_SSID="$OPTARG"
			;;
		c)
			echo "Channel set to $OPTARG" >&2
			CMD_WLAN_CHANNEL="$OPTARG"
			;;
		b)
			echo "Bridge set to $OPTARG" >&2
			CMD_WLAN_BRIDGE="$OPTARG"
			;;
		f)
			echo "Reading configuration file $OPTARG" >&2
			CMD_FILE="$OPTARG"
			;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			usage
			exit 1
			;;
		:)
			echo "Option -$OPTARG requires an argument." >&2
			usage
			exit 1
			;;
	esac
done

if [[ "${!CMD_FILE[@]}" = "0" ]]; then
	if [ -e "$CMD_FILE" ]; then
		source "$CMD_FILE"
	else
		echo "Configuration file '$CMD_FILE' not found" >&1;
		exit 1
	fi
fi

[[ "${!CMD_WLAN_DEV[@]}" = "0" ]] && WLAN_DEV=$CMD_WLAN_DEV
[[ "${!CMD_WLAN_SSID[@]}" = "0" ]] && WLAN_SSID=$CMD_WLAN_SSID
[[ "${!CMD_WLAN_CHANNEL[@]}" = "0" ]] && WLAN_CHANNEL=$CMD_WLAN_CHANNEL
[[ "${!CMD_WLAN_PHY[@]}" = "0" ]] && WLAN_PHY=$CMD_WLAN_PHY
[[ "${!CMD_WLAN_BRIDGE[@]}" = "0" ]] && WLAN_BRIDGE=$CMD_WLAN_BRIDGE


if [ -z "$WLAN_SSID" ]; then
	echo "No ESSID (-s) specified" >&2
	usage
	exit 1
fi

if [ -n "$WLAN_PHY" ]; then
	# create a new VAP
	WLAN_DEV="tb-${WLAN_SSID// /_}"
	WLAN_DEV="${WLAN_DEV:0:15}"

	$IW phy "$WLAN_PHY" interface add "$WLAN_DEV" type __ap || exit 1
	RND_MAC=$(printf "%02x:%02x:%02x:%02x:%02x:%02x" 0x00 0x16 0x3e $(($RANDOM%0x7F)) $(($RANDOM%0xFF)) $(($RANDOM%0xFF)))
	$IP link set dev "$WLAN_DEV" address "$RND_MAC"

	# if no channel has been specified on the command line, we try to find out
	# which channel is used by the hardware
	if [ -z "$WLAN_CHANNEL" ]; then
		# lookup the existing device
		SLAVES=$($IW dev | awk -vP="$WLAN_PHY" '/^phy/ {PHY=$0; gsub("#", "", PHY)} PHY==P && /^[[:space:]]+Interface/ {print $2}')
		for S in $SLAVES; do
			WLAN_CHANNEL=$($IWLIST "$S" channel | sed -nr 's!^.*\(Channel ([0-9]+)\)$!\1!p')
			[ -n "$WLAN_CHANNEL" ] && break;
		done
		echo "Found WLAN channel $WLAN_CHANNEL" >&2
	fi
fi

# No channel set? Revert to default channel (or at least try)
if [ -z "$WLAN_CHANNEL" ]; then
	WLAN_CHANNEL="$WLAN_DEFAULT_CHANNEL"
fi

if [ -z "$WLAN_DEV" ]; then
	echo "No WLAN interface or device specified (-i/-p)" >&2
	usage
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

$IP link set $WLAN_DEV up
$SYSCTL net.ipv4.ip_forward=1
if [ -z "$WLAN_BRIDGE" ]; then
	$IP addr add dev $WLAN_DEV "$WLAN_OWN_ADDRESS"
	$IPTABLES -t nat -A POSTROUTING -s "$WLAN_OWN_ADDRESS" -j MASQUERADE

	$DNSMASQ -z -I lo -i "$WLAN_DEV" --dhcp-range="$WLAN_DHCP_RANGE" -d
else
	$BRCTL addif "$WLAN_BRIDGE" "$WLAN_DEV"
	wait $HOSTAP_PID
fi
