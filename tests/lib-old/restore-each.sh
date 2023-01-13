#!/bin/bash -ex

# shellcheck source=tests/lib/snap-names.sh
. "$TESTSLIBOLD"/snap-names.sh
# shellcheck source=tests/lib/utilities.sh
. "$TESTSLIBOLD"/utilities.sh
get_qemu_eth_iface eth_if

# Remove all snaps not being the core, gadget, kernel or snap we're testing
for snap in /snap/*; do
    snap="${snap:6}"
    case "$snap" in
	README | bin | "$gadget_name" | "$kernel_name" | core* | snapd | "$SNAP_NAME")
	    ;;
	*)
	    snap remove "$snap"
	    ;;
    esac
done

if snap list | grep "$SNAP_NAME" ; then
    snap remove --purge network-manager
fi

rm -f /etc/netplan/*
cat > /etc/netplan/"$DEFAULT_NETPLAN_FILE" <<EOF
network:
  ethernets:
    $eth_if:
      dhcp4: true
  version: 2
EOF

# First generate to avoid netplan trying to restart NM while it does
# not exist anymore.
netplan generate
netplan apply

snap_install network-manager --channel=22/stable
wait_for_network_manager
