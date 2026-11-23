# Ubuntu Desktop running qBittorrent in Xfce4

[ubuntu-desktop-xfce](https://github.com/Fullaxx/ubuntu-desktop-xfce) with [qBittorrent](https://www.qbittorrent.org/), a Qt-based BitTorrent client. \
qBittorrent starts with the desktop and keeps everything (its settings, its torrents and your downloads) on one volume, /data.

## Base Docker Image
[ghcr.io/fullaxx/ubuntu-desktop-xfce](https://github.com/Fullaxx/ubuntu-desktop-xfce):26.04 (Ubuntu 26.04, Xfce 4.20, TigerVNC 1.15)

## Software
* [qBittorrent](https://www.qbittorrent.org/) 5.1.4 - Ubuntu 26.04's package, installed when the image is built
* [Firefox](https://www.mozilla.org/firefox/) - Mozilla's build from the Mozilla Team PPA (Ubuntu's own firefox package is the snap)
* 7-Zip (with RAR support), mktorrent, buildtorrent, curl, wget, file, lsof, ping, mtr, the OpenSSH client, iproute2, net-tools, tree, zip/unzip, bzip2, xz-utils, zstd and bash-completion

## Get the image or build it locally
```
docker pull ghcr.io/fullaxx/ubuntu-desktop-xfce-qbittorrent

docker build -t="ghcr.io/fullaxx/ubuntu-desktop-xfce-qbittorrent" https://github.com/Fullaxx/ubuntu-desktop-xfce-qbittorrent.git
```
`:latest` and `:26.04` (ubuntu-desktop-xfce 26.04) are the same image. It is rebuilt at every push to `master`, with the packages as they are then,
so a rebuild picks up Ubuntu's updates to qBittorrent and Mozilla's to Firefox.

## Volume: /data
Mount a directory on /data to keep your downloads, qBittorrent's settings and its torrents when the container is re-created
```
-v /srv/docker/qbittorrent/data:/data
```
```
/data
|-- autoload   - Drop your .torrent files here (or .magnet files, with one magnet link per line)
|-- torrents   - qBittorrent keeps a copy of every .torrent here
|-- processing - Downloads in progress
|-- complete   - Finished downloads are moved here
`-- config
    |-- config - qBittorrent's settings (~/.config/qBittorrent is a link to it)
    `-- data   - qBittorrent's list of torrents and its logs (~/.local/share/qBittorrent is a link to it)
```
- qBittorrent adds what you drop in autoload within seconds (on a network share, within 10 seconds), then deletes it from autoload.
  A file it can't read is tried 5 times, 10 seconds apart, then renamed to .qbt_rejected: copy a .torrent in under a name
  that doesn't end in .torrent (such as .part), then rename it.
- The folders and qBittorrent's default settings are made at login. The settings are only written when /data/config/config has none, so the settings you change in qBittorrent are kept.
- With `VNCUSERMAP`, the desktop user is given everything in the folders that belongs to someone else, at every login (only those files change). As root (the default), no owner changes.
- qBittorrent keeps a lock file and a socket in /data/config/config, which an SMB/CIFS share may not support.
  With /data on such a share, mount a local directory or a Docker volume on /data/config too: `-v /srv/docker/qbittorrent/config:/data/config`

## Incoming connections
qBittorrent listens on port 6881, TCP and UDP (set by its default settings; Tools > Options > Connection changes it). \
Publish it so that peers can connect to you (not when qBittorrent is on a VPN container's network: [NETWORKING.md](NETWORKING.md#qbittorrents-incoming-port))
```
-p 6881:6881 -p 6881:6881/udp
```

## VPN
qBittorrent has no VPN of its own: run it on the network of a VPN container, and its traffic goes through the VPN. \
How to set that up, with an OpenVPN and a WireGuard example: [NETWORKING.md](NETWORKING.md)

## Firefox
Firefox is in the image: Applications > Ubuntu Desktop > Network > Browsers > Firefox. \
Give the container more shared memory, or Firefox's tabs crash ([why](https://github.com/Fullaxx/ubuntu-desktop-xfce/blob/master/troubleshooting/WEB_BROWSERS.md))
```
--shm-size 2g
```

## Magnet links
Firefox in the container's desktop sends the magnet links you click to qBittorrent: [MAGNET_LINKS.md](MAGNET_LINKS.md)

## The first login
qBittorrent is in the image: it starts with the desktop, and nothing is installed at login. \
Closing qBittorrent's window leaves it running, with its icon in the panel's tray: File > Exit quits it. \
qBittorrent's log is in /data/config/data/logs.

## Desktop Options
Everything in ubuntu-desktop-xfce's README works the same here: \
[VNC Options](https://github.com/Fullaxx/ubuntu-desktop-xfce#vnc-options) /
[Non-root users](https://github.com/Fullaxx/ubuntu-desktop-xfce#non-root-users) /
[TimeZone](https://github.com/Fullaxx/ubuntu-desktop-xfce#timezone-configuration) /
[Locale](https://github.com/Fullaxx/ubuntu-desktop-xfce#locale-configuration) /
[Input Method](https://github.com/Fullaxx/ubuntu-desktop-xfce#input-method-configuration) /
[Wallpaper](https://github.com/Fullaxx/ubuntu-desktop-xfce#wallpaper-configuration) /
[Extra privileges](https://github.com/Fullaxx/ubuntu-desktop-xfce/blob/master/PRIVILEGES.md) /
[Troubleshooting](https://github.com/Fullaxx/ubuntu-desktop-xfce/tree/master/troubleshooting)

## Run the image
Run the image on localhost port 5901, with your downloads and qBittorrent's settings in /srv/docker/qbittorrent/data
```
docker run -d -p 127.0.0.1:5901:5901 -p 6881:6881 -p 6881:6881/udp \
-v /srv/docker/qbittorrent/data:/data ghcr.io/fullaxx/ubuntu-desktop-xfce-qbittorrent
```
Run the image with a named volume
```
docker volume create qbittorrent-data
docker run -d -p 127.0.0.1:5901:5901 -p 6881:6881 -p 6881:6881/udp \
-v qbittorrent-data:/data ghcr.io/fullaxx/ubuntu-desktop-xfce-qbittorrent
```
Run the image as the built-in ubuntu user account
```
docker run -d -p 127.0.0.1:5901:5901 -p 6881:6881 -p 6881:6881/udp \
-e VNCUSERMAP='ubuntu/1000' \
-v /srv/docker/qbittorrent/data:/data ghcr.io/fullaxx/ubuntu-desktop-xfce-qbittorrent
```
Run the image in Denver, with a 1920x1080 desktop and a VNC password
```
docker run -d -p 127.0.0.1:5901:5901 -p 6881:6881 -p 6881:6881/udp \
-e TZ='America/Denver' -e VNCRES='1920x1080' -e VNCPASS='vncpass' \
-v /srv/docker/qbittorrent/data:/data ghcr.io/fullaxx/ubuntu-desktop-xfce-qbittorrent
```
Run the image so that it comes back with a fresh desktop after you log out
```
docker run -d --restart unless-stopped -p 127.0.0.1:5901:5901 -p 6881:6881 -p 6881:6881/udp \
-v /srv/docker/qbittorrent/data:/data ghcr.io/fullaxx/ubuntu-desktop-xfce-qbittorrent
```

## Connect using vncviewer or a web browser
Use any standard VNC client to connect directly. \
For web access, check out [noVNC](https://github.com/Fullaxx/novnc) to access your container with a web browser.
```
vncviewer 127.0.0.1:5901
```

## How it works
At login, Xfce runs [xfce4/qbittorrent_autostart.sh](xfce4/qbittorrent_autostart.sh) (from /etc/xdg/autostart) as the desktop user:
1. It runs [scripts/prepare_qbittorrent.sh](scripts/prepare_qbittorrent.sh) as root, through sudo (ubuntu-desktop-xfce's sudo rules allow /app/scripts/prepare_*.sh),
   which makes the folders, copies the default settings if there are none, removes the lock file a stopped container left behind,
   and gives a non-root desktop user what's in the folders.
2. It links ~/.config/qBittorrent to /data/config/config and ~/.local/share/qBittorrent to /data/config/data, so qBittorrent keeps its settings and torrents there.
3. It runs ubuntu-desktop-xfce's /app/scripts/qbittorrent.sh, which starts qBittorrent.

If /data can't be prepared, if something other than those links is in the way, or if the desktop user can't write to one of the folders,
a message on the desktop says so. \
After you quit qBittorrent, Applications > Ubuntu Desktop > Network > BitTorrent > qBittorrent starts it again. \
To keep it from starting at login, turn it off in Settings > Session and Startup > Application Autostart.

The default settings, [conf/qBittorrent.conf](conf/qBittorrent.conf) and [conf/watched_folders.json](conf/watched_folders.json), set only these:
| Setting | Value |
| --- | --- |
| Downloads > Default Save Path | /data/complete |
| Downloads > Use another path for incomplete torrents | on, /data/processing |
| Downloads > Copy .torrent files to | /data/torrents |
| Downloads > Automatically add torrents from | /data/autoload |
| Connection > Port used for incoming connections | 6881 |
| BitTorrent > Torrent Queueing | off, as in a new qBittorrent profile |
| The legal notice | accepted, so qBittorrent doesn't show it at its first start |
| Meta\MigrationVersion | 8, qBittorrent 5.1.4's: qBittorrent takes these settings as new ones, not as old ones to convert |

Check the whole path on a Docker host (CI runs this before it publishes)
```
tests/qbittorrent.sh ghcr.io/fullaxx/ubuntu-desktop-xfce-qbittorrent
tests/qbittorrent.sh ghcr.io/fullaxx/ubuntu-desktop-xfce-qbittorrent -e VNCUSERMAP=ubuntu/1000
```

## Coming from fullaxx/qbittorrent
- /data is still the one volume: /data/autoload works as before, new downloads go to /data/complete, and what's in /data/dl stays there.
- OpenVPN is no longer built in, and neither are its options (OVPNCFG, OVPNKS, ...), GATEWAY or the /config mount.
  Run qBittorrent on a VPN container's network instead: [NETWORKING.md](NETWORKING.md)
- Drop the mounts on /root/.config/qBittorrent and /root/.local: ~/.config/qBittorrent and ~/.local/share/qBittorrent are links to /data now.
  To keep your settings and your torrents, copy them into /data before the new container's first start (here with the old README's paths)
  ```
  mkdir -p /srv/docker/qbt/data/config
  cp -a /srv/docker/qbt/home/qbt /srv/docker/qbt/data/config/config
  cp -a /srv/docker/qbt/home/local/share/qBittorrent /srv/docker/qbt/data/config/data
  ```
  qBittorrent then runs with your old settings, such as downloads to /data/dl, its log in /data/logs, its old port and /data/autoload,
  which Tools > Options changes. Without them, it starts with the new settings: add your torrents again.
- VNCUSER/VNCUID were replaced by VNCUSERMAP: [Non-root users](https://github.com/Fullaxx/ubuntu-desktop-xfce#non-root-users)
