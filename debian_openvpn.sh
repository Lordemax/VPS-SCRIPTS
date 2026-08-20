#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run this installer as root." >&2
  exit 1
fi
. /etc/os-release
if [[ ${ID_LIKE:-$ID} != *debian* && ${ID:-} != ubuntu ]]; then
  echo "This installer supports Debian-based systems." >&2
  exit 1
fi

read -r -p "OpenVPN port [1194]: " PORT
PORT=${PORT:-1194}
read -r -p "Client name [client]: " CLIENT
CLIENT=${CLIENT:-client}
if [[ ! $PORT =~ ^[0-9]+$ || ! $CLIENT =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "Invalid port or client name." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y openvpn easy-rsa iptables iptables-persistent curl

SERVER_DIR=/etc/openvpn/server
PKI_DIR=$SERVER_DIR/pki
mkdir -p "$SERVER_DIR"
if [[ ! -f $PKI_DIR/pki/ca.crt ]]; then
  rm -rf "$PKI_DIR"
  make-cadir "$PKI_DIR"
  cd "$PKI_DIR"
  ./easyrsa init-pki
  EASYRSA_BATCH=1 EASYRSA_REQ_CN=VPS-CA ./easyrsa build-ca nopass
  EASYRSA_BATCH=1 ./easyrsa gen-req server nopass
  EASYRSA_BATCH=1 ./easyrsa sign-req server server
  EASYRSA_BATCH=1 ./easyrsa gen-dh
fi

cd "$PKI_DIR"
if [[ ! -f pki/issued/$CLIENT.crt ]]; then
  EASYRSA_BATCH=1 ./easyrsa gen-req "$CLIENT" nopass
  EASYRSA_BATCH=1 ./easyrsa sign-req client "$CLIENT"
fi

cat >"$SERVER_DIR/server.conf" <<EOF
port $PORT
proto tcp-server
dev tun
user nobody
group nogroup
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 1.0.0.1"
keepalive 10 60
persist-key
persist-tun
ca $PKI_DIR/pki/ca.crt
cert $PKI_DIR/pki/issued/server.crt
key $PKI_DIR/pki/private/server.key
dh $PKI_DIR/pki/dh.pem
cipher AES-256-GCM
data-ciphers AES-256-GCM:AES-128-GCM
auth SHA256
status /var/log/openvpn/status.log
verb 3
EOF

IP=$(curl -4fsS https://api.ipify.org || hostname -I | awk '{print $1}')
OUT=/root/ovpn-$CLIENT
mkdir -p "$OUT"
cat >"$OUT/$CLIENT.ovpn" <<EOF
client
dev tun
proto tcp-client
remote $IP $PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
data-ciphers AES-256-GCM:AES-128-GCM
auth SHA256
verb 3
<ca>
$(cat "$PKI_DIR/pki/ca.crt")
</ca>
<cert>
$(cat "$PKI_DIR/pki/issued/$CLIENT.crt")
</cert>
<key>
$(cat "$PKI_DIR/pki/private/$CLIENT.key")
</key>
EOF

IFACE=$(ip -o route show to default | awk '{print $5; exit}')
sysctl -w net.ipv4.ip_forward=1 >/dev/null
printf 'net.ipv4.ip_forward=1\n' >/etc/sysctl.d/99-openvpn-forward.conf
iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o "$IFACE" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$IFACE" -j MASQUERADE
netfilter-persistent save
systemctl enable --now openvpn-server@server
tar -czf "/root/ovpn-$CLIENT.tar.gz" -C "$OUT" "$CLIENT.ovpn"
rm -rf "$OUT"
echo "Client profile: /root/ovpn-$CLIENT.tar.gz"
