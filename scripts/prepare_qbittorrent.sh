#!/bin/bash
# This script runs as root
# /data for qBittorrent: its folders and qBittorrent's default config, for the desktop user who runs it through sudo
# (/usr/local/bin/qbittorrent_autostart.sh does, at every login: the base image's sudo rules let the desktop
# user run /app/scripts/prepare_*.sh). Running it again only adds what's missing.

FOLDERS="/data/autoload /data/torrents /data/processing /data/complete /data/config /data/config/config /data/config/data"

# The folders the default config points at, and qBittorrent's own: ~/.config/qBittorrent is a link to
# /data/config/config (its settings), ~/.local/share/qBittorrent to /data/config/data (its torrents and logs)
mkdir -p ${FOLDERS} || exit 1

# qBittorrent's default config, only if there is no config yet: a /data kept from an earlier container keeps its settings
if [ ! -e /data/config/config/qBittorrent.conf ]; then
  install -m 0644 /usr/share/qbittorrent/qBittorrent.conf.default /data/config/config/qBittorrent.conf || exit 1
  if [ ! -e /data/config/config/watched_folders.json ]; then
    install -m 0644 /usr/share/qbittorrent/watched_folders.json.default /data/config/config/watched_folders.json || exit 1
  fi
fi

# qBittorrent's lock file and socket stay behind when the container stops with qBittorrent running.
# A lock file that qBittorrent can't open (another user's, which a filesystem refused to chown) makes it
# think it's running already, and it exits: without a qBittorrent running, they can go
if ! pgrep -x qbittorrent >/dev/null; then
  rm -f /data/config/config/lockfile /data/config/config/ipc-socket
fi

# A non-root desktop user (VNCUSERMAP) gets whatever in the folders has another owner, such as what root
# wrote when the container ran without VNCUSERMAP. A root desktop needs nothing, so it changes no owner.
# Best effort: some filesystems refuse chown (NFS with root_squash, CIFS), and qbittorrent_autostart.sh
# shows which folders the desktop user can't write
if [ "${SUDO_UID:-0}" != "0" ]; then
  if ! find ${FOLDERS} \( ! -user "${SUDO_UID}" -o ! -group "${SUDO_GID}" \) -exec chown -h "${SUDO_UID}:${SUDO_GID}" {} +; then
    echo "$0: some of /data could not be given to ${SUDO_USER} (${SUDO_UID}:${SUDO_GID})" >&2
  fi
fi
