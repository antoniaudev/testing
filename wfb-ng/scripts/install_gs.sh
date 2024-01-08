#!/bin/bash
set -e

if [[ $# -eq 0 ]] ; then
    echo 'Please specify the name of the WiFi adapter'
    echo 'Find the name using command: ip a'
    echo 'Aborting ...'
    exit 1
fi

IFNAME="${1}"

# Install required packages
apt update
apt upgrade

apt install python3-all libpcap-dev libsodium-dev python3-pip python3-pyroute2 \
  python3-future python3-twisted python3-serial iw virtualenv debhelper dh-python build-essential -y

# Build
make deb

# Create key and copy to right location
./wfb_keygen
mv gs.key /etc/gs.key

# Install
dpkg -i deb_dist/*.deb 

# Setup config
cat <<EOF >> /etc/wifibroadcast.cfg
[common]
wifi_region = 'AU'     # Your country for CRDA (use BO or GY if you want max tx power)  
wifi_freqs = {'wlx00c0cab55a77': 5745, 'wlx00c0cab2a558': 5805}
set_nm_unmanaged = True   # Set radio interface in 'unmanaged state' in NetworkManager
radio_mtu = 1445          # Used for mavlink aggregation and for tunnel packets - should be less or equal to MAX_PAYLOAD_SIZE, don't change if doubt
tunnel_agg_timeout= 0.005 # aggragate tuntap packets if less than radio_mtu but no longer than 5ms
mavlink_agg_timeout = 0.1 # aggragate mavlink packets if less than radio_mtu but no longer than 100ms
mavlink_err_rate = True   # If true then inject RX error rate else absolute values
tx_sel_delta = 3          # hysteresis for antenna selection, [dB]
tx_rcv_buf_size = 524288  # UDP SO_RCVBUF. Set 0 to use net.core.rmem_default. Increase in case of non-cbr data stream

[base]
stream_rx = None
stream_tx = None
keypair = None
show_stats = True
mirror = False     # Set to true if you want to mirror packet via all cards for redundancy. Not recommended if cards are on one frequency channel.

# Radio settings for TX and RX
bandwidth = 20     # bandwidth 20 or 40 MHz

# Radiotap flags for TX:
short_gi = False   # use short GI or not
stbc = 1           # stbc streams: 1, 2, 3 or 0 if unused
ldpc = 1           # use LDPC FEC. Currently available only for 8812au and must be supported both on TX and RX.
mcs_index = 1      # mcs index


[gs_mavlink]
peer = 'connect://127.0.0.1:14550'  # outgoing connection
# peer = 'listen://0.0.0.0:14550'   # incoming connection

[gs_video]
peer = 'connect://127.0.0.1:5600'  # outgoing connection for
                                   # video sink (QGroundControl on GS)
EOF

echo "WFB_NICS=\"${IFNAME}\"" > /etc/default/wifibroadcast

cat <<EOF >> /etc/NetworkManager/NetworkManager.conf
[keyfile]
unmanaged-devices=interface-name:${IFNAME}
EOF

if [ -f /etc/dhcpcd.conf ]; then
    echo "denyinterfaces ${IFNAME}" >> /etc/dhcpcd.conf
fi

# Start gs service
systemctl daemon-reload
systemctl start wifibroadcast@gs

echo "Started wifibroadcast@gs"
systemctl status wifibroadcast@gs
