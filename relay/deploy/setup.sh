#!/bin/sh
# One-command setup of a DLChat private relay on a fresh Debian or Ubuntu server, run as root:
#   scp -r relay root@SERVER:/root/ && ssh root@SERVER sh /root/relay/deploy/setup.sh
# Installs Tor from the distribution, builds nothing on the server (copy the prebuilt binary to
# /root/relay/dlchat-relay first, see README), runs the relay as an unprivileged user on 127.0.0.1,
# and publishes it only as a Tor onion service. Prints the onion address to put in the app.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
BIN="$HERE/../dlchat-relay"
[ -x "$BIN" ] || { echo "Missing $BIN (build it with: GOOS=linux GOARCH=amd64 go build -o dlchat-relay .)"; exit 1; }

apt-get update -q
apt-get install -y -q tor

id dlchat-relay >/dev/null 2>&1 || useradd --system --home /var/lib/dlchat-relay --create-home --shell /usr/sbin/nologin dlchat-relay
install -m 0755 "$BIN" /usr/local/bin/dlchat-relay
install -m 0644 "$HERE/dlchat-relay.service" /etc/systemd/system/dlchat-relay.service

if ! grep -q "dlchat-relay" /etc/tor/torrc; then
  cat "$HERE/torrc.snippet" >> /etc/tor/torrc
fi

# Nothing but SSH and Tor's own outgoing connections: the relay is never on a public port.
if command -v ufw >/dev/null 2>&1; then ufw allow OpenSSH >/dev/null; ufw --force enable >/dev/null; fi

systemctl daemon-reload
systemctl enable --now dlchat-relay
systemctl restart tor
sleep 5
echo "Onion address for DLChat:"
cat /var/lib/tor/dlchat-relay/hostname
