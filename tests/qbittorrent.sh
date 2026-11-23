#!/bin/bash
# Start an ubuntu-desktop-xfce-qbittorrent image the way users do and check the whole path: the image's tools,
# Firefox and qBittorrent's magnet link handler, the desktop, /data's folders, qBittorrent's settings and torrents on /data,
# qBittorrent running with the default config (listening on 6881), and a .torrent dropped in /data/autoload added,
# copied to /data/torrents and removed from /data/autoload. Options after the image go to docker run, such as a
# non-root desktop user. Run it on a Docker host, as .github/workflows/ci.yml does before it publishes:
#   tests/qbittorrent.sh IMAGE
#   tests/qbittorrent.sh IMAGE -e VNCUSERMAP=ubuntu/1000

set -euo pipefail

IMAGE="${1:?usage: ${0##*/} IMAGE [docker run options]}"
shift
NAME="udxq-test-$$"
PORT=6881
FOLDERS="/data/autoload /data/torrents /data/processing /data/complete /data/config/config /data/config/data"
CONFIG=/data/config/config/qBittorrent.conf

fail() {
  echo "FAIL: $*" >&2
  docker logs --tail 40 "${NAME}" 2>&1 || true
  exit 1
}

running() {
  [ "$(docker inspect -f '{{.State.Running}}' "${NAME}" 2>/dev/null)" == "true" ]
}

# wait_for SECONDS MESSAGE COMMAND...: run COMMAND every second until it succeeds, or fail with MESSAGE
wait_for() {
  local SECS="$1" MSG="$2"
  shift 2
  for _ in $(seq "${SECS}"); do
    running || fail "${IMAGE} exited (${MSG})"
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  fail "${MSG}"
}

# -v: the container's anonymous /data volume goes with it
trap 'docker rm -f -v "${NAME}" >/dev/null 2>&1 || true' EXIT

docker run -d --name "${NAME}" "$@" "${IMAGE}" >/dev/null

# The image: qBittorrent, Firefox and the tools the Dockerfile installs (7zip-rar gives 7z its RAR codec)
for TOOL in qbittorrent firefox 7z buildtorrent mktorrent ping ip lsof netstat tree file zip unzip zstd mtr ssh; do
  docker exec "${NAME}" which "${TOOL}" >/dev/null || fail "${TOOL} is not installed"
done
SEVENZIP=$(docker exec "${NAME}" 7z i)
grep -q -E '^ *[0-9]+ +[A-Z]* +[0-9A-F]+ +Rar5$' <<<"${SEVENZIP}" || fail "7z lists no RAR codec (7zip-rar)"
# Firefox is Mozilla's build, from the Mozilla Team PPA (Ubuntu's own firefox package is a transition to the snap)
FIREFOX=$(docker exec "${NAME}" firefox --version 2>/dev/null || true)
[[ "${FIREFOX}" == "Mozilla Firefox "* ]] || fail "firefox is not Mozilla's build from the Mozilla Team PPA (firefox --version: ${FIREFOX})"
# qBittorrent's desktop entry makes it the desktop's handler for magnet links, which Firefox asks the desktop for
docker exec "${NAME}" grep -q -x -F 'x-scheme-handler/magnet=org.qbittorrent.qBittorrent.desktop;' /usr/share/applications/mimeinfo.cache \
  || fail "qBittorrent is not the desktop's handler for magnet links"

# The desktop: a VNC server speaks first, with an RFB ProtocolVersion banner such as "RFB 003.008",
# and Xfce starts after it, from its xstartup
BANNER=""
for _ in $(seq 60); do
  running || fail "${IMAGE} exited before the desktop came up"
  BANNER=$(docker exec "${NAME}" timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/5901 && head -c 12 <&3' 2>/dev/null || true)
  if [[ "${BANNER}" == RFB* ]]; then
    break
  fi
  sleep 1
done
[[ "${BANNER}" == RFB* ]] || fail "no VNC server answered on 127.0.0.1:5901 within 60 s"
wait_for 30 "the VNC server is up but xfce4-session did not start within 30 s" docker exec "${NAME}" pgrep -x xfce4-session

# The desktop user (root, or VNCUSERMAP's) and its HOME
SESSIONUID=$(docker exec "${NAME}" ps -o uid= -C xfce4-session)
SESSIONUID="${SESSIONUID//[[:space:]]/}"
SESSIONHOME=$(docker exec "${NAME}" getent passwd "${SESSIONUID}" | cut -d: -f6)

# /data, from qbittorrent_autostart.sh at login: the folders, and qBittorrent's settings (~/.config/qBittorrent)
# and its torrents and logs (~/.local/share/qBittorrent) on /data
wait_for 60 "${SESSIONHOME}/.local/share/qBittorrent did not appear within 60 s of the login" \
  docker exec "${NAME}" test -L "${SESSIONHOME}/.local/share/qBittorrent"
[ "$(docker exec "${NAME}" readlink "${SESSIONHOME}/.config/qBittorrent")" == "/data/config/config" ] \
  || fail "${SESSIONHOME}/.config/qBittorrent is not a link to /data/config/config"
[ "$(docker exec "${NAME}" readlink "${SESSIONHOME}/.local/share/qBittorrent")" == "/data/config/data" ] \
  || fail "${SESSIONHOME}/.local/share/qBittorrent is not a link to /data/config/data"
for DIR in ${FOLDERS}; do
  docker exec "${NAME}" test -d "${DIR}" || fail "${DIR} is missing"
done

# qBittorrent, started at login, on the default config's listen port (without it, a new profile picks a random port)
wait_for 120 "qBittorrent did not start within 120 s" docker exec "${NAME}" pgrep -x qbittorrent
wait_for 60 "qBittorrent is running but does not listen on ${PORT}" docker exec "${NAME}" timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/${PORT}"

# The default config, once qBittorrent has rewritten it (it adds its random SSL port then): every setting is kept.
# qBittorrent replaces the file, which is briefly missing, so each check is retried
wait_for 60 "qBittorrent did not write its settings to ${CONFIG} within 60 s" docker exec "${NAME}" grep -q '^Session\\SSL\\Port=' "${CONFIG}"
for SETTING in 'Session\DefaultSavePath=/data/complete' 'Session\Port=6881' 'Session\QueueingSystemEnabled=false' \
               'Session\TempPath=/data/processing' 'Session\TempPathEnabled=true' 'Session\TorrentExportDirectory=/data/torrents' \
               'Accepted=true' 'MigrationVersion=8'; do
  wait_for 10 "${CONFIG} lost ${SETTING}" docker exec "${NAME}" grep -q -x -F "${SETTING}" "${CONFIG}"
done
docker exec "${NAME}" grep -q -F '"/data/autoload"' /data/config/config/watched_folders.json || fail "/data/autoload is not a watched folder"

# A non-root desktop user owns everything in the folders (prepare_qbittorrent.sh), qBittorrent's files included
if [ "${SESSIONUID}" != "0" ]; then
  OTHERS=$(docker exec "${NAME}" find ${FOLDERS} ! -user "${SESSIONUID}")
  [ -z "${OTHERS}" ] || fail "not owned by UID ${SESSIONUID}: ${OTHERS}"
fi

# A .torrent dropped in /data/autoload: qBittorrent adds it (its list of torrents is in /data/config/data/BT_backup),
# copies it to /data/torrents and removes it from /data/autoload. It's written as .part and then renamed, so
# qBittorrent never reads half a file
docker exec "${NAME}" sh -c 'head -c 65536 /dev/urandom > /tmp/udxq-test.bin &&
  mktorrent -a http://127.0.0.1:1/announce -o /data/autoload/udxq-test.part /tmp/udxq-test.bin >/dev/null &&
  mv /data/autoload/udxq-test.part /data/autoload/udxq-test.torrent' || fail "mktorrent could not make a test torrent"
wait_for 60 "the .torrent in /data/autoload was not copied to /data/torrents within 60 s" \
  docker exec "${NAME}" test -e /data/torrents/udxq-test.bin.torrent
wait_for 30 "the .torrent in /data/autoload was not removed within 30 s" docker exec "${NAME}" test ! -e /data/autoload/udxq-test.torrent
docker exec "${NAME}" sh -c 'ls /data/config/data/BT_backup | grep -q "\.torrent$"' || fail "the torrent is not in /data/config/data/BT_backup"

echo "OK: ${IMAGE}${*:+ ($*)} runs Xfce, prepares /data for UID ${SESSIONUID}, starts qBittorrent, which listens on ${PORT} and adds from /data/autoload"
