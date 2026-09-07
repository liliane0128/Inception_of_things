#!/bin/bash
set -eu

: "${NODE_IP:?NODE_IP must be set}"
: "${SERVER_IP:?SERVER_IP must be set}"
: "${K3S_TOKEN:?K3S_TOKEN must be set}"

# Attendre que l'API du serveur soit prête avant de tenter de le rejoindre
until curl -ksS "https://${SERVER_IP}:6443" >/dev/null; do
	sleep 2
done

# Détecter l'interface réseau correspondant à l'IP privée, pour que Flannel
# l'utilise plutôt que l'interface NAT par défaut
IFACE=$(ip -4 -o addr show | awk -v ip="$NODE_IP" '$4 ~ "^"ip"/" {print $2; exit}')

curl -sfL https://get.k3s.io | \
	K3S_URL="https://${SERVER_IP}:6443" \
	K3S_TOKEN="${K3S_TOKEN}" \
	INSTALL_K3S_VERSION="v1.36.3+k3s1" \
	INSTALL_K3S_EXEC="agent --node-ip=${NODE_IP} --flannel-iface=${IFACE}" \
	sh -