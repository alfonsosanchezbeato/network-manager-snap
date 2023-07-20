#!/bin/sh -ex
# Copyright (C) 2016-2018 Canonical Ltd
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Functions to apply snap settings

# Replace content of file if current content is different
# $1: file
# $2: new content
_replace_file_if_diff() {
    old_content=
    if [ -e "$1" ]; then
        old_content=$(cat "$1") || true
    fi
    if [ "$2" != "$old_content" ]; then
        echo "Replacing $1"
        echo "$2" > "$1"
    fi
}

# Disable wifi powersave
# $1: enabled/disabled literal string
_switch_wifi_powersave() {
    path=$SNAP_DATA/conf.d/wifi-powersave.conf
    # See https://developer.gnome.org/libnm/stable/NMSettingWireless.html#NMSettingWirelessPowersave
    # for the meaning of the different values for the wifi.powersave option.
    case $1 in
        enabled)
            content=$(printf "[connection]\nwifi.powersave = 3")
            ;;
        disabled)
            content=$(printf "[connection]\nwifi.powersave = 2")
            ;;
        *)
            echo "WARNING: invalid value '$1' supplied for wifi.powersave configuration option"
            return
            ;;
    esac
    _replace_file_if_diff "$path" "$content"
}

# Set WoWLAN configuration
# $1: disabled/any/disconnect/magic/gtk-rekey-failure/eap-identity-request/
#     4way-handshake/rfkill-release/tcp literal string. They
#     correspond to the enum NMSettingWirelessWakeOnWLan defined
#     in libnm-core. NetworkManager only allows us to set integer
#     values here. This still needs to be upstreamed: see
#     https://mail.gnome.org/archives/networkmanager-list/2017-January/thread.html
# $2: WoWLAN activation password
_switch_wifi_wake_on_wlan() {
    value=0
    case "$1" in
        disabled)
            value=0
            ;;
        any)
            value=2
            ;;
        disconnect)
            value=4
            ;;
        magic)
            value=8
            ;;
        gtk-rekey-failure)
            value=16
            ;;
        eap-identity-request)
            value=32
            ;;
        4way-handshake)
            value=64
            ;;
        rfkill-release)
            value=128
            ;;
        tcp)
            value=256
            ;;
        *)
            echo "WARNING: Invalid value provided for wifi.wake-on-wlan"
            return
            ;;
    esac
    password=$2
    path=$SNAP_DATA/conf.d/wifi-wowlan.conf

    content=$(printf "[connection]")
    # If we don't get a value provided there is not one set in the snap
    # configuration and we can simply leave it out here and let
    # NetworkManager take its default one.
    if [ -n "$value" ]; then
        content=$(printf "%s\nwifi.wake-on-wlan=%s" "$content" "$value")
    fi
    if [ -n "$password" ]; then
        content=$(printf "%s\nwifi.wake-on-wlan-password=%s" "$content" "$password")
    fi

    _replace_file_if_diff "$path" "$content"
}

# Enable debug mode
# $1: true/false literal string
_switch_debug_enable() {
    DEBUG_FILE=$SNAP_DATA/.debug_enabled
    # $1 true/false for enabling/disabling debug log level in nm
    # We create/remove the file for future executions and also change
    # the logging level of the running daemon.
    if [ "$1" = "true" ]; then
        touch "$DEBUG_FILE"
    else
        rm -f "$DEBUG_FILE"
    fi
}

# Enable/disable connectivity check
# $1: uri
# $2: interval
# $3: response
_switch_connectivity_check() {
    path=$SNAP_DATA/conf.d/connectivity.conf
    if [ -z "$1" ]; then
        rm -f "$path"
        return
    fi

    content=$(printf "[connectivity]\nuri=%s" "$1")
    if [ -n "$2" ]; then
        content=$(printf "%s\ninterval=%s" "$content" "$2")
    fi
    if [ -n "$3" ]; then
        content=$(printf "%s\nresponse=%s" "$content" "$3")
    fi

    _replace_file_if_diff "$path" "$content"
}

# Set/unset NM as default netplan renderer
# $1: true/false
_switch_defaultrenderer() {
    path=/etc/netplan/00-default-nm-renderer.yaml

    # Remove related configuration file from older NM snap versions.
    # We let netplan do whatever is needed.
    rm -f "$SNAP_DATA"/conf.d/disable-ethernet.conf

    if [ "$1" = true ] || [ "$1" = yes ]; then
        if [ ! -f "$path" ]; then
            printf "network:\n  renderer: NetworkManager\n" > "$path"
            dbus-send --system --type=method_call --print-reply \
                      --dest=io.netplan.Netplan /io/netplan/Netplan \
                      io.netplan.Netplan.Apply
            # Flush ips of devices that now we control. Workaround
            # until LP:#1870561 is fixed.
            for conn_f in /run/NetworkManager/system-connections/*; do
                if ifname=$(grep ^interface-name= "$conn_f"); then
                    ifname=${ifname#interface-name=}
                    ip address flush dev "$ifname" || true
                fi
            done
        fi
    elif [ -f "$path" ]; then
        rm -f "$path"
        dbus-send --system --type=method_call --print-reply \
                  --dest=io.netplan.Netplan /io/netplan/Netplan \
                  io.netplan.Netplan.Apply
    fi
}

# Update NetworkManager.conf plugins
# $1: what the plugins should be
_switch_plugins() {

    # Create custom NetworkManager.conf from template if it doesn't already exist.
    # From now on, $SNAP_DATA/NetworkManager.conf will be used.
    if [ ! -f "$SNAP_DATA"/NetworkManager.conf  ];then
        cp "$SNAP"/etc/NetworkManager/NetworkManager.conf "$SNAP_DATA"
    fi

    sed -i "s/^plugins=.*/plugins=$1/" "$SNAP_DATA"/NetworkManager.conf
}

# shellcheck source=snap-prop.sh
. "$SNAP"/bin/snap-prop.sh

apply_snap_config() {
    _switch_wifi_powersave "$(get_wifi_powersave)"
    _switch_wifi_wake_on_wlan "$(get_wifi_wake_on_wlan)" "$(get_wifi_wake_on_password)"
    _switch_debug_enable "$(get_debug_enable)"
    _switch_connectivity_check "$(get_property connectivity.uri)" \
                               "$(get_property connectivity.interval)" \
                               "$(get_property connectivity.response)"
    _switch_defaultrenderer "$(get_defaultrenderer)"
    _switch_plugins "$(get_plugins)"
}
