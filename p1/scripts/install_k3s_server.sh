#!/bin/bash
set -eu

: "${NODE_IP:?NODE_IP must be set}"
: "${K3S_TOKEN:?K3S_TOKEN must be set}"

# Détecter l'interface réseau correspondant à l'IP privée, pour que Flannel
# l'utilise plutôt que l'interface NAT par défaut
IFACE=$(ip -4 -o addr show | awk -v ip="$NODE_IP" '$4 ~ "^"ip"/" {print $2; exit}')

curl -sfL https://get.k3s.io | K3S_TOKEN="${K3S_TOKEN}" \
	INSTALL_K3S_VERSION="v1.36.3+k3s1" \
	INSTALL_K3S_EXEC="server \
		--node-ip=${NODE_IP} \
		--advertise-address=${NODE_IP} \
		--tls-san=${NODE_IP} \
		--flannel-iface=${IFACE} \
		--write-kubeconfig-mode=644" \
	sh -

{
	echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
	echo "alias k=kubectl"
} >> /home/vagrant/.bashrc