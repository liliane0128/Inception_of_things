#!/usr/bin/env bash
set -eu

IFACE=$(ip -4 -o addr show | awk -v ip="$NODE_IP" '$4 ~ "^"ip"/" {print $2; exit}')

curl -sfL https://get.k3s.io | K3S_TOKEN="$K3S_TOKEN" \
	INSTALL_K3S_EXEC="server \
		--node-ip=${NODE_IP} \
		--advertise-address=${NODE_IP} \
		--tls-san=${NODE_IP} \
		--flannel-iface=${IFACE} \
		--write-kubeconfig-mode=644" \
	sh -

# k3s's installer already provides a working `kubectl` (symlinked to the k3s
# binary, defaults to /etc/rancher/k3s/k3s.yaml) -- that satisfies "install kubectl".
{
	echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
	echo "alias k=kubectl"
} >>/home/vagrant/.bashrc
