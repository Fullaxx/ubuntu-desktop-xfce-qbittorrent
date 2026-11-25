# ------------------------------------------------------------------------------
# Base Image : ghcr.io/fullaxx/ubuntu-desktop-xfce:26.04 (https://github.com/Fullaxx/ubuntu-desktop-xfce)
#              Ubuntu 26.04 LTS (Resolute Raccoon), Xfce 4.20, TigerVNC 1.15
# Support    : Apr 2026 - May 2031
FROM ghcr.io/fullaxx/ubuntu-desktop-xfce:26.04
LABEL author="Brett Kuskie <fullaxx@gmail.com>"

# ------------------------------------------------------------------------------
# Add the Mozilla Team PPA, for Firefox
# (the base image's script, the one its Firefox and Thunderbird launchers run: the PPA's key, its sources, and a pin
# above Ubuntu's archive, whose firefox package is a transition to the snap; the lists from its apt-get update are
# cleaned up here)
RUN /app/scripts/prepare_mozilla_ppa_direct.sh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/tmp/* /tmp/*

# ------------------------------------------------------------------------------
# Install qBittorrent, Firefox and tools, and clean up
# (7zip-rar comes from multiverse, which the base image's apt sources include)
# APT_REFRESH: CI passes its run id, so that each CI run installs Ubuntu's and the PPA's packages as they are then,
# instead of reusing a cached layer
ARG APT_REFRESH
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      7zip \
      7zip-rar \
      bash-completion \
      buildtorrent \
      bzip2 \
      ca-certificates \
      curl \
      file \
      firefox \
      iproute2 \
      iputils-ping \
      lsof \
      mktorrent \
      mtr-tiny \
      net-tools \
      openssh-client \
      qbittorrent \
      tree \
      unzip \
      wget \
      xz-utils \
      zip \
      zstd && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/tmp/* /tmp/*

# ------------------------------------------------------------------------------
# Provide default qBittorrent config
# (/app/scripts/prepare_qbittorrent.sh copies it to /data/config/config when qBittorrent has no config there yet)
COPY conf/qBittorrent.conf /usr/share/qbittorrent/qBittorrent.conf.default
COPY conf/watched_folders.json /usr/share/qbittorrent/watched_folders.json.default

# ------------------------------------------------------------------------------
# Install scripts and configuration files
# (the desktop user runs prepare_qbittorrent.sh through sudo: the base image's sudo rules allow /app/scripts/prepare_*.sh)
COPY scripts/prepare_qbittorrent.sh /app/scripts/
# Xfce starts qBittorrent at login (/etc/xdg/autostart is only for .desktop files, the scripts go on PATH)
COPY xfce4/qbittorrent_autostart.sh /usr/local/bin/
COPY xfce4/qbittorrent_autostart.desktop /etc/xdg/autostart/

# ------------------------------------------------------------------------------
# Identify Volumes
VOLUME /data

# ------------------------------------------------------------------------------
# Expose ports
# (qBittorrent's listen port, from the default config; the base image exposes VNC's 5901)
EXPOSE 6881/tcp 6881/udp

# ------------------------------------------------------------------------------
# Define default command
# (ubuntu-desktop-xfce's startup, unchanged)
CMD ["/app/app.sh"]
