# failover-router

Vibe coded script to share internet over LAN. Aka turn a computer into a router.

The typical use case: the main router is down, so you plug a phone into a Linux computer, enable USB tethering, and share that connection over Ethernet to the other computers on the LAN. The script handles DHCP, DNS and NAT through NetworkManager's built-in "shared" mode.

```
 phone (USB tether) --> [ this computer ] --> switch --> other computers
        usb0 / enx...                eth0 / end0
        (source_if)                  (share_if)
```

## Requirements

- Linux with NetworkManager (`nmcli`)
- `dnsmasq-base` (NetworkManager uses it for DHCP and DNS in shared mode)
- Root access (`sudo`)

Install `dnsmasq-base`, not the full `dnsmasq` package. The full package runs its own system service, which can conflict with NetworkManager's instance.
Or Install `dnsmasq` and disable the `dnsmasq` service.

## Usage

```bash
# Start routing
sudo ./failover-router.sh route <source_if> <share_if> [gateway_ip/prefix]

# Stop routing and clean up
sudo ./failover-router.sh disable
```

| Argument | Description |
|---|---|
| `source_if` | Interface that has internet, e.g. a phone tether (`usb0`, `enx...`) |
| `share_if` | Interface to share it out on, e.g. `eth0` or `end0` |
| `gateway_ip/prefix` | Optional. Defaults to `10.42.0.1/24` |

Find your interface names with:

```bash
nmcli device status
```

### Examples

```bash
# Share a USB-tethered phone over eth0
sudo ./failover-router.sh route usb0 eth0

# Same, but take over the dead router's IP so clients with a static gateway keep working
sudo ./failover-router.sh route usb0 eth0 192.168.1.1/24

# Router is back, turn it off
sudo ./failover-router.sh disable
```

## What it does

`route`:

1. Checks that both interfaces exist and that the source has a default route.
2. Warns if internet traffic currently leaves through a different interface.
3. Creates a NetworkManager profile (`Failover-Router`) on the share interface with `ipv4.method shared`.
4. Activates it. NetworkManager then runs DHCP and DNS and sets up NAT.

`disable` brings the profile down and deletes it.

The profile has autoconnect turned off, so it never starts by itself. That avoids running two DHCP servers on the LAN once the real router is back.

## Notes

- Clients may need to renew their DHCP lease or replug their cable before they pick up the new gateway.
- If the computer is still connected to the dead router, disconnect that link first. NAT goes out through whichever interface holds the default route.
- Turn this off when the main router comes back. Two DHCP servers on one LAN will cause problems.
- IPv4 only. IPv6 is ignored on the share interface.

## Troubleshooting

**`Connection activation failed: IP configuration could not be reserved`**

Usually one of these:

1. `dnsmasq` isn't installed. Run `which dnsmasq`.
2. The share interface has no link. Check `cat /sys/class/net/<share_if>/carrier` (should print `1`).
3. The share interface is `unmanaged`. Check `nmcli device status`.
4. Subnet conflict with the default `10.42.0.0/24`. Pass a different `gateway_ip/prefix`.

For details:

```bash
journalctl -u NetworkManager -n 50 --no-pager | grep -iE "dnsmasq|shared"
```

**Clients get an address but have no internet**

- Confirm the source interface works: `ping -I <source_if> 1.1.1.1`
- Check that the default route is on the source interface: `ip route get 1.1.1.1`

## Disclaimer

Vibe coded and lightly tested. Read the script before running it as root.