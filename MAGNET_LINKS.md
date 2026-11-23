# Configuring Magnet Links

Firefox in the container's desktop can send the magnet links you click to qBittorrent. \
Firefox is in the image: Applications > Ubuntu Desktop > Network > Browsers > Firefox.

## Firefox
qBittorrent's desktop entry makes it the desktop's application for magnet links, and Firefox asks the desktop which
application to use, so there's nothing to set up:
* Click any magnet link. Firefox asks whether to allow the site to open the magnet link with qBittorrent
* Click "Open Link" (check "Always allow" first, and it stops asking for that site)
* qBittorrent opens a window to add the torrent: click OK

The torrent goes to the running qBittorrent. If qBittorrent isn't running, the link starts it.
