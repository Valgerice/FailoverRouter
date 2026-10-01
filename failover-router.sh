#!/usr/bin/env bash
#
# failover-router.sh
#
# Turns this Linux machine into a temporary LAN router/gateway when the main
# router is down: take internet from one interface (e.g. a phone USB-tethered
# as usb0 / enx...) and share it out over another (e.g. eth0) to other
# computers, with DHCP + NAT handled by NetworkManager.
#
# Usage:
#   sudo ./failover-router.sh route <source_if> <share_if> [gateway_ip/prefix]
#   sudo ./failover-router.sh disable
#
# Examples:
#   sudo ./failover-router.sh route usb0 eth0
#   sudo ./failover-router.sh route usb0 eth0 192.168.1.1/24   # take over the dead router's IP
#
# Tip: find your interface names with:  nmcli device status

CONN_NAME="Failover-Router"

usage() {
  cat <<EOF
Usage:
  sudo $0 route <source_if> <share_if> [gateway_ip/prefix]
  sudo $0 disable

  source_if         interface that HAS internet (e.g. phone tether: usb0, enx...)
  share_if          interface to share it out on (e.g. eth0, towards the switch)
  gateway_ip/prefix optional; defaults to 10.42.0.1/24. Set this to the dead
                    router's address (e.g. 192.168.1.1/24) so clients that
                    already use it as their gateway keep working.

Examples:
  sudo $0 route usb0 eth0
  sudo $0 route usb0 eth0 192.168.1.1/24
  sudo $0 disable
EOF
  exit 1
}

if [ "$EUID" -ne 0 ]; then
  echo "Error: please run this script with sudo." >&2
  exit 1
fi

if ! command -v nmcli >/dev/null 2>&1; then
  echo "Error: nmcli (NetworkManager) is required." >&2
  exit 1
fi

case "${1:-}" in
  route)
    SOURCE_IF="${2:-}"
    SHARE_IF="${3:-}"
    GATEWAY_CIDR="${4:-}"

    if [ -z "$SOURCE_IF" ] || [ -z "$SHARE_IF" ]; then
      echo "Error: missing network interfaces." >&2
      usage
    fi

    if [ "$SOURCE_IF" = "$SHARE_IF" ]; then
      echo "Error: source and share interfaces must be different." >&2
      exit 1
    fi

    for IF in "$SOURCE_IF" "$SHARE_IF"; do
      if ! ip link show "$IF" >/dev/null 2>&1; then
        echo "Error: interface '$IF' does not exist (see: nmcli device status)." >&2
        exit 1
      fi
    done

    # The source interface must actually have internet access to share.
    if ! ip -4 route show default dev "$SOURCE_IF" | grep -q .; then
      echo "Error: '$SOURCE_IF' has no default route. Is the phone tether connected and up?" >&2
      exit 1
    fi

    # NetworkManager NATs out through whatever interface carries the default
    # route, so warn if that is not the interface the user asked for.
    CURRENT_OUT=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1)
    if [ -n "$CURRENT_OUT" ] && [ "$CURRENT_OUT" != "$SOURCE_IF" ]; then
      echo "Warning: internet traffic currently leaves via '$CURRENT_OUT', not '$SOURCE_IF'." >&2
      echo "         Disconnect '$CURRENT_OUT' or raise its route metric, or sharing may not use the tether." >&2
    fi

    echo "Configuring sharing: $SOURCE_IF (internet) -> $SHARE_IF (LAN)..."

    # Remove any old profile so settings are always fresh
    nmcli connection delete "$CONN_NAME" >/dev/null 2>&1

    ARGS=(
      type ethernet
      ifname "$SHARE_IF"
      con-name "$CONN_NAME"
      ipv4.method shared          # DHCP + DNS + NAT
      ipv6.method ignore
      connection.autoconnect no   # never start on its own once the real router is back
    )
    if [ -n "$GATEWAY_CIDR" ]; then
      ARGS+=(ipv4.addresses "$GATEWAY_CIDR")
    fi

    if ! nmcli connection add "${ARGS[@]}" >/dev/null; then
      echo "Error: failed to create connection profile." >&2
      exit 1
    fi

    if ! nmcli connection up "$CONN_NAME"; then
      echo "Error: failed to activate sharing. Cleaning up." >&2
      nmcli connection delete "$CONN_NAME" >/dev/null 2>&1
      exit 1
    fi

    echo "Done. $SHARE_IF is now serving DHCP and routing via $SOURCE_IF."
    echo "Clients may need to renew their lease or reconnect their cable."
    echo "Run '$0 disable' once the main router is back."
    ;;

  disable)
    echo "Disabling sharing and cleaning up..."

    if nmcli -t -f NAME connection show | grep -qx "$CONN_NAME"; then
      nmcli connection down "$CONN_NAME" >/dev/null 2>&1
      nmcli connection delete "$CONN_NAME" >/dev/null
      echo "Connection profile '$CONN_NAME' removed."
    else
      echo "No '$CONN_NAME' profile found, nothing to remove."
    fi

    echo "Sharing disabled. Reconnect the share interface to your normal LAN profile if needed."
    ;;

  *)
    usage
    ;;
esac
