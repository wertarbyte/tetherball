#!/bin/sh
IWCONFIG="iwconfig"
IP="ip"
HOSTAPD="hostapd"
DNSMASQ="dnsmasq"
SYSCTL="sysctl"
IPTABLES="iptables"

WLAN_DEV="wlan0"
AP_CONF="$(mktemp hostapd-${WLAN_DEV}-XXXXX --tmpdir --suffix=.conf)"

WLAN_SSID="test"
WLAN_PSK="secretstuff"
WLAN_OWN_ADDRESS="10.9.9.1/24"
WLAN_DHCP_RANGE="10.9.9.100-10.9.9.150,1h"

cat <<EOF > "$AP_CONF"
interface=$WLAN_DEV
ssid=$WLAN_SSID
hw_mode=g
channel=1
beacon_int=100
dtim_period=2
max_num_sta=255
rts_threshold=2347
fragm_threshold=2346
macaddr_acl=0
auth_algs=3
ignore_broadcast_ssid=0
wmm_enabled=1
wmm_ac_bk_cwmin=4
wmm_ac_bk_cwmax=10
wmm_ac_bk_aifs=7
wmm_ac_bk_txop_limit=0
wmm_ac_bk_acm=0
wmm_ac_be_aifs=3
wmm_ac_be_cwmin=4
wmm_ac_be_cwmax=10
wmm_ac_be_txop_limit=0
wmm_ac_be_acm=0
wmm_ac_vi_aifs=2
wmm_ac_vi_cwmin=3
wmm_ac_vi_cwmax=4
wmm_ac_vi_txop_limit=94
wmm_ac_vi_acm=0
wmm_ac_vo_aifs=2
wmm_ac_vo_cwmin=2
wmm_ac_vo_cwmax=3
wmm_ac_vo_txop_limit=47
wmm_ac_vo_acm=0
eapol_key_index_workaround=0
eap_server=0
own_ip_addr=127.0.0.1
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

$DNSMASQ -i wlan0 --dhcp-range 10.9.9.100,10.9.9.150,255.255.255.0,1h -d

# cleanup
kill $HOSTAP_PID
rm "$AP_CONF"
$IPTABLES -t nat -D POSTROUTING -s "$WLAN_OWN_ADDRESS" -j MASQUERADE
$IP addr del dev $WLAN_DEV "$WLAN_OWN_ADDRESS"
$IP link set $WLAN_DEV down
