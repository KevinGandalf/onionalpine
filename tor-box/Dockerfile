# Tor-Box: offizieller Tor Browser in einem Container, Bedienung im Web-Browser
# (noVNC), optional hinter WireGuard oder OpenVPN mit Killswitch.
FROM debian:bookworm-slim

ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg dirmngr jq xz-utils \
      tigervnc-standalone-server novnc websockify python3-websockify openbox \
      supervisor wireguard-tools openvpn iptables iproute2 procps \
      libgtk-3-0 libdbus-glib-1-2 libasound2 libx11-xcb1 libxt6 libxtst6 libpci3 \
      fonts-dejavu-core \
 && rm -rf /var/lib/apt/lists/*

# Unprivilegierter Benutzer für Desktop und Browser
RUN useradd -m -u 1000 -s /bin/bash app \
 && install -d -o app -g app /home/app/Downloads \
 && install -d -m 1777 /tmp/.X11-unix

# Tor Browser herunterladen und Signatur gegen den Schlüssel der
# Tor-Browser-Entwickler prüfen. Ohne gültige Signatur bricht der Bau ab.
ARG TB_KEY=EF6E286DDA85EA2A4BA7DE684E2C6E8793298290
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) plat=linux-x86_64 ;; \
      arm64) plat=linux-aarch64 ;; \
      *) echo "Architektur ${TARGETARCH} wird nicht unterstützt" >&2; exit 1 ;; \
    esac; \
    cd /tmp; \
    curl -fsSL -o downloads.json https://aus1.torproject.org/torbrowser/update_3/release/downloads.json; \
    bin=$(jq -er --arg p "$plat" '.downloads[$p].ALL.binary' downloads.json); \
    sig=$(jq -er --arg p "$plat" '.downloads[$p].ALL.sig' downloads.json); \
    case "$bin" in https://dist.torproject.org/*) ;; *) echo "unerwartete URL: $bin" >&2; exit 1 ;; esac; \
    curl -fsSL -o tb.tar.xz "$bin"; \
    curl -fsSL -o tb.tar.xz.asc "$sig"; \
    export GNUPGHOME="$(mktemp -d)"; \
    gpg --batch --auto-key-locate nodefault,wkd --locate-keys torbrowser@torproject.org \
      || curl -fsSL "https://keys.openpgp.org/vks/v1/by-fingerprint/${TB_KEY}" | gpg --batch --import; \
    gpg --batch --status-fd 1 --verify tb.tar.xz.asc tb.tar.xz > verify.txt; \
    grep -Eq "^\[GNUPG:\] VALIDSIG .* ${TB_KEY}\$" verify.txt; \
    mkdir -p /opt; \
    tar -xJf tb.tar.xz -C /opt; \
    test -x /opt/tor-browser/Browser/start-tor-browser; \
    jq -r .version downloads.json > /opt/tor-browser/VERSION.txt; \
    rm -rf /tmp/tb.tar.xz* /tmp/downloads.json /tmp/verify.txt "$GNUPGHOME"

# Profil-Voreinstellungen: automatisch mit Tor verbinden, deutsche Oberfläche
RUN prof=/opt/tor-browser/Browser/TorBrowser/Data/Browser/profile.default \
 && mkdir -p "$prof" \
 && printf '%s\n' \
      'user_pref("torbrowser.settings.quickstart.enabled", true);' \
      'user_pref("intl.locale.requested", "de,en-US");' \
      > "$prof/user.js" \
 && chown -R app:app /opt/tor-browser

# Fenster ohne Rahmen und maximiert
RUN sed -i 's#<applications>#<applications><application class="*"><decor>no</decor><maximized>yes</maximized></application>#' \
      /etc/xdg/openbox/rc.xml

# wg-quick will einen sysctl setzen, den Docker schon setzt (und der im
# Container schreibgeschützt ist). Nur setzen, wenn er noch nicht stimmt.
RUN sed -i 's#\[\[ $proto == -4 \]\] && cmd sysctl -q net\.ipv4\.conf\.all\.src_valid_mark=1#[[ $proto == -4 ]] \&\& [[ $(sysctl -n net.ipv4.conf.all.src_valid_mark) != 1 ]] \&\& cmd sysctl -q net.ipv4.conf.all.src_valid_mark=1#' \
      /usr/bin/wg-quick \
 && grep -q 'sysctl -n net.ipv4.conf.all.src_valid_mark' /usr/bin/wg-quick

COPY rootfs/ /
RUN chmod 0755 /usr/local/bin/*

EXPOSE 6080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
