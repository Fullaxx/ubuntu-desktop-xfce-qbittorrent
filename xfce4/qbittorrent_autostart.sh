#!/bin/bash

# Started at xfce4 login by /etc/xdg/autostart/qbittorrent_autostart.desktop, as the desktop user:
# /data for qBittorrent (prepare_qbittorrent.sh, through sudo), qBittorrent's settings and torrents on /data,
# then qBittorrent itself

FOLDERS="/data/autoload /data/torrents /data/processing /data/complete /data/config/config /data/config/data"

# /data's folders and qBittorrent's default config, prepared as root for this user
PREPARED=$(sudo -n /app/scripts/prepare_qbittorrent.sh 2>&1)
if [ $? -ne 0 ]; then
  xmessage -center "qBittorrent was not started: /data could not be prepared
${PREPARED}" &
  exit 1
fi
# Its warnings, if any, go to the session log
if [ -n "${PREPARED}" ]; then
  echo "${PREPARED}" >&2
fi

# qBittorrent keeps its settings in ~/.config/qBittorrent, and its list of torrents and its logs in
# ~/.local/share/qBittorrent: links to /data/config/config and /data/config/data keep them on the volume
NOTLINKED=""
link_to_data() {
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then
    if mkdir -p "$(dirname "$1")" && ln -s "$2" "$1"; then
      return
    fi
  elif [ "$(readlink "$1")" == "$2" ]; then
    return
  fi
  NOTLINKED="${NOTLINKED}
$1 is not a link to $2"
}
link_to_data "${HOME}/.config/qBittorrent" /data/config/config
link_to_data "${HOME}/.local/share/qBittorrent" /data/config/data
if [ -n "${NOTLINKED}" ]; then
  xmessage -center "qBittorrent's settings and torrents are not kept on /data:${NOTLINKED}" &
fi

# Folders this user can't write (prepare_qbittorrent.sh couldn't give them to it): qBittorrent starts anyway
NOTWRITABLE=""
for DIR in ${FOLDERS}; do
  if [ ! -w "${DIR}" ]; then
    NOTWRITABLE="${NOTWRITABLE} ${DIR}"
  fi
done
if [ -n "${NOTWRITABLE}" ]; then
  xmessage -center "qBittorrent: $(id -un) can't write to${NOTWRITABLE}" &
fi

# ubuntu-desktop-xfce's launcher: qBittorrent is in the image, so it just starts it
exec /app/scripts/qbittorrent.sh
