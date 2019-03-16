#!/usr/bin/env bash

WLAN_SSID=drahtlooser
WLAN_PASSWORD="$(pass show "priv/wlan/${WLAN_SSID}")"

export WLAN_SSID
export WLAN_PASSWORD

./make_sd.sh
