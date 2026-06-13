# Phase 3 — UniFi Port Mirror (feeding traffic to the Pi)

Goal: make the **USW Ultra 60W** send a *copy* of your network's traffic to the
port **jmacpi2** is plugged into, so Suricata can actually see your devices.

This is a switch-config phase — no changes to the repo or the Pi's software.

---

## 0. The big idea (recap)

A switch normally sends each packet only to the port that needs it, so the Pi
never sees other devices' traffic. **Port mirroring** tells the switch: "copy
everything from port X and also send it to the Pi's port." It's a copy — the
real traffic is untouched, nothing slows down. The Pi watches from the side
(out-of-band) and can't interfere.

You mirror the **uplink port** (the one going to the **Gateway Lite**), because
*all* internet traffic funnels through it. That single source covers all ~45
devices.

```
Internet ── [Gateway Lite] ──(uplink port = MIRROR SOURCE)── [USW Ultra] ──(Pi port = MIRROR DESTINATION)── jmacpi2 eth0
                                                                  │
                                                          phones / laptops / TV / IoT
```

---

## 1. ⚠️ READ THIS FIRST — the connectivity gotcha

On almost all switches (UniFi included), a **mirror *destination* port becomes
receive-only**: it spits out mirrored copies but **drops** the device's normal
traffic. So if you mirror to the port `eth0` is on, **the Pi loses its own
network on that cable** — no SSH, no internet, no Tailscale. That would brick
your access.

The Pi needs **two separate network paths**: one for *management* (SSH,
Tailscale, Docker pulls) and one *dedicated* to receiving the mirror. Pick one:

| Option | Management path | Mirror (Suricata) path | `SURICATA_INTERFACE` in `.env` |
|---|---|---|---|
| **A. Wi-Fi for mgmt (recommended, no extra hardware)** | Pi's built-in Wi-Fi (`wlan0`) | `eth0` (the mirror destination) | `eth0` |
| **B. USB Ethernet adapter** | `eth0` (normal port) | USB NIC, usually `eth1` | `eth1` (whatever it enumerates as) |

**Option A** is simplest — the Pi 5 has Wi-Fi built in. Connect the Pi to your
Wi-Fi for management, leave `eth0` cabled to the switch as the mirror target.
`SURICATA_INTERFACE=eth0` (your current `.env`) stays correct.

**Option B** is the "proper tap" setup if you'd rather keep management on
wired Ethernet — but you must buy a USB Ethernet adapter and update
`SURICATA_INTERFACE` to its name (run `ip -o link show` on the Pi to find it,
e.g. `eth1` or `enxXXXXXXXX`).

> Do this BEFORE enabling the mirror, or the moment you save the mirror you'll
> lose SSH to the Pi.

If you went with **Option A**: on the Pi, set up Wi-Fi with
`sudo nmtui` (or `sudo raspi-config` → System Options → Wireless LAN), confirm
`ping -c1 1.1.1.1` works over Wi-Fi, then verify you can reach it at its Wi-Fi
address before touching the switch.

### Option A — make Wi-Fi the default route (REQUIRED, easy to miss)

By default the Pi prefers the wired link for *all* traffic (lower route
metric), so even with Wi-Fi connected the internet still goes out `eth0`:

```bash
ip route show default
# default via 192.168.2.1 dev eth0  proto dhcp metric 100   <- wins
# default via 192.168.2.1 dev wlan0 proto dhcp metric 600
```

The moment the mirror makes `eth0` receive-only, that `eth0` default route
becomes a black hole and the Pi loses internet (Docker pulls, apt, Tailscale)
even though SSH-over-Wi-Fi still works. Fix it by demoting `eth0`'s route
metric below `wlan0`'s.

On Raspberry Pi OS with **NetworkManager + netplan** (connections named
`netplan-eth0` etc.), edit the eth0 netplan file under `/etc/netplan/` and add
the two override blocks:

```yaml
    eth0:
      renderer: NetworkManager
      dhcp4: true
      dhcp6: true
      dhcp4-overrides:
        route-metric: 1000      # higher than wlan0's 600 = least preferred
      dhcp6-overrides:
        route-metric: 1000
      # ...leave the existing networkmanager: uuid/name block intact...
```

Then apply and **reboot** (a reboot is the reliable way to flush the old DHCP
lease's stale metric-100 route — applying in place tends to leave duplicate
default routes and can briefly drop NetworkManager):

```bash
sudo netplan generate && sudo reboot
```

After reboot, confirm Wi-Fi is now the default path:

```bash
ip route show default      # eth0 metric 1000, wlan0 metric 600 (no metric 100)
ip route get 1.1.1.1       # must say: dev wlan0
```

Only once `1.1.1.1` routes via `wlan0` is it safe to enable the mirror.

---

## 2. Set up the mirror in the UniFi console

Exact labels shift between UniFi Network versions; the path is conceptually the
same. (Tested against UniFi Network 8/9.)

1. Open the **UniFi Network** app (your console's local IP, or
   `https://unifi.ui.com`).
2. Left sidebar → **UniFi Devices** → click the **USW Ultra 60W**.
3. In the device panel, open **Port Manager** (older versions: the **Ports**
   tab).
4. Click the **port the Pi is plugged into** — this will be the **mirror
   DESTINATION**.
5. In that port's settings, find **Port Mirror** (may be under an
   **Advanced** / **More** toggle). Enable it.
6. Set the **Mirror Source** to the **uplink port** — the port connected to the
   **Gateway Lite** (it's labeled as the uplink / WAN-facing port, often the
   one with the "uplink" arrow icon).
7. **Apply / Queue Changes** and let the switch provision (a few seconds).

> If your firmware only lets you mirror to a port — i.e. you configure it *on*
> the destination port and choose a source — that's exactly what step 4–6
> describe. If instead it asks you to configure it *on the source* port and
> choose a destination, mirror **uplink → Pi port**; same result.

### Which port is the "uplink"?
The one connecting the switch to the **Gateway Lite**. In Port Manager it's
usually flagged as the uplink. If unsure, it's the port whose cable runs to the
gateway — unplug-and-watch in the UI if you must (briefly).

---

## 3. Verify the Pi is now seeing traffic

SSH to the Pi (over Wi-Fi if you chose Option A) and watch Suricata's capture:

```bash
# Are packets arriving on the mirror interface? (rising RX counters = good)
ip -s link show eth0          # or your Option-B interface

# Watch Suricata's capture stats — 'pkts' should climb fast
sudo suricatasc -c "iface-stat eth0"

# Watch events land in real time (you should see dns events from other devices)
sudo tail -f /var/lib/siem/suricata/eve.json | grep --line-buffered '"event_type":"dns"'
```

If you see **DNS events with `src_ip`s that are NOT the Pi's own address**
(e.g. your phone or laptop looking things up), the mirror is working — the Pi
is now seeing the whole network.

Then open Grafana → **Devices Calling Out** dashboard. Within a minute the
"DNS queries by device" and "Top destinations by source device" panels should
start showing multiple devices.

---

## 4. Troubleshooting

| Symptom | Likely cause |
|---|---|
| Lost SSH the instant you saved the mirror | You mirrored to the Pi's *management* port. Revert; use a separate path (Section 1). |
| Only see the Pi's own IP in events | Mirror not active, or you mirrored the wrong source port (mirror the **uplink**, not an empty port). |
| `RX` counters on the interface aren't climbing | Cable in the wrong switch port, or mirror destination set to a different port than the Pi's. |
| Suricata `capture.kernel_drops` rising fast | Too much mirrored traffic for the Pi. Expected to be fine on a 1Gbps home LAN with DNS+alerts; if not, mirror fewer ports. |

---

## 5. What's next

Once you see other devices' DNS in `eve.json` and on the dashboard, Phase 3 is
done. Continue to **Phase 4** (deploy/confirm the stack — if not already done),
then **Phase 5** (Tailscale + Telegram) and **Phase 6** (harden + verify).
