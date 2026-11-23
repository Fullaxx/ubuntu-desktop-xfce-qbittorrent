# qBittorrent on a VPN container's network

qBittorrent has no VPN of its own. It can use the network of another container instead: a VPN container connects to your VPN,
qBittorrent runs on that container's network, and qBittorrent's traffic follows the VPN's routes.
It takes nothing more than docker run's `--network container:<name>` (or `network_mode: "service:<name>"` in Docker Compose).

Any VPN container works the same way. These are two examples:
[ghcr.io/fullaxx/openvpn](https://github.com/Fullaxx/openvpn) for OpenVPN, and
[lscr.io/linuxserver/wireguard](https://docs.linuxserver.io/images/docker-wireguard/) for WireGuard.

- [What moves to the VPN container](#what-moves-to-the-vpn-container)
- [Publishing VNC (5901)](#publishing-vnc-5901)
- [Example: OpenVPN](#example-openvpn)
- [Example: WireGuard](#example-wireguard)
- [qBittorrent's incoming port](#qbittorrents-incoming-port)
- [Restarting](#restarting)
- [Check it](#check-it)
- [Troubleshooting](#troubleshooting)

## What moves to the VPN container
`--network container:<name>` puts qBittorrent in the VPN container's network namespace: qBittorrent has the VPN container's interfaces,
routes and address, and the same /etc/resolv.conf, /etc/hosts and hostname.
So the docker run options that set up a network go on the VPN container. Docker refuses them on qBittorrent, with a "conflicting options" error.

| docker run option | Goes on |
| --- | --- |
| `-p` (publishing a port, such as VNC's 5901) | the VPN container |
| `--dns` | the VPN container (qBittorrent uses its /etc/resolv.conf) |
| `-h` / `--hostname`, `--add-host` | the VPN container |
| `--network container:<name>` | qBittorrent |
| `-e`, `-v`, `--shm-size`, `--restart` | qBittorrent, as usual |

## Publishing VNC (5901)
Publish VNC on the VPN container, on 127.0.0.1
```
-p 127.0.0.1:5901:5901
```
A VNC client on the host connects to 127.0.0.1:5901, where Docker's docker-proxy listens.
docker-proxy then makes its own connection to the VPN container's address, from the gateway address of the container's Docker network
(172.17.0.1 on Docker's default bridge), so tigervncserver sees a client on its own network:
```
vncviewer      --> 127.0.0.1:5901                 docker-proxy, on the host
docker-proxy   --> <VPN container's address>:5901  from 172.17.0.1
tigervncserver --> 172.17.0.1                      its reply, out through eth0
```
Why it has to be done this way: the VPN sends everything else into its tunnel.
- OpenVPN's redirect-gateway adds routes for 0.0.0.0/1 and 128.0.0.0/1 through tun0.
- WireGuard (wg-quick, with `AllowedIPs = 0.0.0.0/0`) sends everything through wg0 with policy routing, except addresses that a more specific local route covers.

The connection from docker-proxy comes from an address on the container's own network: tigervncserver's reply to it goes out
through eth0, the only addresses that still do.
Publish 5901 on every address instead (`-p 5901:5901`) and connect from another machine, and Docker's NAT hands the connection
to tigervncserver with that machine's address: the replies go into the tunnel, and the VNC client hangs.
LinuxServer.io's WireGuard docs warn of the same thing for web UIs.

From another machine, go through the host with an SSH tunnel, then point the VNC client at localhost:5901
```
ssh -L 5901:127.0.0.1:5901 user@dockerhost
```
A noVNC container on the same Docker network as the VPN container works too: it connects from an address on that network.

The desktop listens on every address the VPN container has, the tunnel's included, so give it a password (on the qBittorrent container)
```
-e VNCPASS='vncpass'
```

## Example: OpenVPN
[ghcr.io/fullaxx/openvpn](https://github.com/Fullaxx/openvpn) connects with the .ovpn profiles in the directory mounted on /profiles.
- By default it goes through every profile in turn, reconnecting inside the same container. `-e RANDOMIZE_PROFILE_LIST=1` shuffles them.
  To keep using one profile, put only that profile in the directory.
- `-e CONFIGFILE=myprofile.ovpn` uses only that profile, and the container exits when the connection ends (see [Restarting](#restarting)).
- Files that a profile names, such as certificates or an auth-user-pass file, are looked up in /profiles.

Start the VPN container, then qBittorrent on its network \
(`-t`: the VPN container's output reaches `docker logs` as it happens)
```
docker run -d -t --name openvpn --restart unless-stopped \
--cap-add=NET_ADMIN --device /dev/net/tun \
--dns 8.8.8.8 --dns 1.1.1.1 \
-p 127.0.0.1:5901:5901 \
-v /srv/docker/openvpn/profiles:/profiles:ro \
ghcr.io/fullaxx/openvpn:alpine

docker run -d --name qbittorrent --restart unless-stopped \
--network container:openvpn \
-e VNCPASS='vncpass' \
-v /srv/docker/qbittorrent/data:/data \
ghcr.io/fullaxx/ubuntu-desktop-xfce-qbittorrent
```
- `--cap-add=NET_ADMIN --device /dev/net/tun` let OpenVPN make its tunnel.
- The openvpn image's `ENABLEMASQ` and `--sysctl net.ipv4.ip_forward=1` are for routing other containers through it.
  qBittorrent uses its network instead, so neither is needed.

The same with Docker Compose
```yaml
services:
  openvpn:
    image: ghcr.io/fullaxx/openvpn:alpine
    restart: unless-stopped
    tty: true
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    dns:
      - 8.8.8.8
      - 1.1.1.1
    ports:
      - 127.0.0.1:5901:5901
    volumes:
      - /srv/docker/openvpn/profiles:/profiles:ro

  qbittorrent:
    image: ghcr.io/fullaxx/ubuntu-desktop-xfce-qbittorrent
    restart: unless-stopped
    network_mode: "service:openvpn"
    depends_on:
      openvpn:
        condition: service_started
        restart: true
    environment:
      - VNCPASS=vncpass
    volumes:
      - /srv/docker/qbittorrent/data:/data
```

## Example: WireGuard
[lscr.io/linuxserver/wireguard](https://docs.linuxserver.io/images/docker-wireguard/) runs as a WireGuard client when `PEERS` isn't set.
Put your VPN provider's WireGuard config in its config directory, as wg_confs/wg0.conf
```
/srv/docker/wireguard/config/wg_confs/wg0.conf
```
Start the VPN container, then qBittorrent on its network
```
docker run -d --name wireguard --restart unless-stopped \
--cap-add=NET_ADMIN \
--sysctl net.ipv4.conf.all.src_valid_mark=1 \
-e PUID=1000 -e PGID=1000 -e TZ='Etc/UTC' \
-p 127.0.0.1:5901:5901 \
-v /srv/docker/wireguard/config:/config \
lscr.io/linuxserver/wireguard:latest

docker run -d --name qbittorrent --restart unless-stopped \
--network container:wireguard \
-e VNCPASS='vncpass' \
-v /srv/docker/qbittorrent/data:/data \
ghcr.io/fullaxx/ubuntu-desktop-xfce-qbittorrent
```
- `--cap-add=NET_ADMIN` lets WireGuard make its interface, and LinuxServer.io's docs list the `src_valid_mark` sysctl as "Required for client mode".
- `PUID` and `PGID` own the files in the config directory.
- If the host's WireGuard kernel module isn't loaded, add `--cap-add=SYS_MODULE -v /lib/modules:/lib/modules:ro`, so the container can load it.
- The config's `DNS =` line sets the VPN container's /etc/resolv.conf, which qBittorrent uses.
- Port 51820, in LinuxServer.io's own examples, is for running a WireGuard server: a client doesn't need it.

The same with Docker Compose
```yaml
services:
  wireguard:
    image: lscr.io/linuxserver/wireguard:latest
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
    ports:
      - 127.0.0.1:5901:5901
    volumes:
      - /srv/docker/wireguard/config:/config

  qbittorrent:
    image: ghcr.io/fullaxx/ubuntu-desktop-xfce-qbittorrent
    restart: unless-stopped
    network_mode: "service:wireguard"
    depends_on:
      wireguard:
        condition: service_started
        restart: true
    environment:
      - VNCPASS=vncpass
    volumes:
      - /srv/docker/qbittorrent/data:/data
```

## qBittorrent's incoming port
Don't publish 6881 when qBittorrent is on a VPN container's network: peers can only reach it through the VPN.
If your VPN provider forwards a port to you, set qBittorrent's listen port to that one: Tools > Options > Connection,
"Port used for incoming connections".

## Restarting
qBittorrent stays on the network of the VPN container it started with: after the VPN container restarts or is re-created, restart qBittorrent too
```
docker restart openvpn
docker restart qbittorrent
```
With Docker Compose, `depends_on` (with `restart: true`) restarts qBittorrent whenever Compose restarts the VPN container
```
docker compose restart openvpn
```
The openvpn image reconnects inside the same container when it goes through its profiles, which leaves qBittorrent alone.
With `CONFIGFILE`, the container exits when its connection ends: restart qBittorrent once the VPN container is back.

## Check it
The routes qBittorrent uses (iproute2 is in the image)
```
docker exec qbittorrent ip route
docker exec qbittorrent ip rule
```
- With OpenVPN, 0.0.0.0/1 and 128.0.0.0/1 go through tun0.
- With WireGuard, `ip rule` sends everything WireGuard hasn't marked to table 51820, and `docker exec qbittorrent ip route show table 51820` has its default route through wg0.

The address the internet sees, from qBittorrent and then from the host: they should differ
```
docker exec qbittorrent curl -s https://icanhazip.com
curl -s https://icanhazip.com
```
The VPN container's log
```
docker logs -f openvpn
docker logs -f wireguard
```
The openvpn image's own tools: its network state and addresses, and a jump to the next profile
```
docker exec -it openvpn /app/debug.sh
docker exec -it openvpn /app/cycle.sh
```

## Troubleshooting
- Docker refuses `-p`, `--dns` or `-h` on qBittorrent ("conflicting options"): they go on the VPN container ([What moves to the VPN container](#what-moves-to-the-vpn-container)).
- OpenVPN logs `Cannot open TUN/TAP dev /dev/net/tun`: the VPN container needs `--cap-add=NET_ADMIN --device /dev/net/tun`.
- OpenVPN logs IPv6 errors such as `RTNETLINK answers: Permission denied`: add `--sysctl net.ipv6.conf.all.disable_ipv6=0` to the VPN container.
- WireGuard logs IPv6 errors: LinuxServer.io's docs say to leave only `0.0.0.0/0` in the config's `AllowedIPs` (remove `::/0`).
- qBittorrent has no network after the VPN container restarted: `docker restart qbittorrent` ([Restarting](#restarting)).
- A VNC client on another machine hangs: see [Publishing VNC (5901)](#publishing-vnc-5901).
