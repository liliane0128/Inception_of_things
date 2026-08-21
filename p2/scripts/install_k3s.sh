#!/usr/bin/env bash
set -eu

# Find the NIC that owns NODE_IP (the private_network interface), so flannel
# uses that link instead of the NAT/default interface.
IFACE=$(ip -4 -o addr show | awk -v ip="$NODE_IP" '$4 ~ "^"ip"/" {print $2; exit}')

# Single-node cluster: install k3s in server mode only, no agent to join.
# INSTALL_K3S_VERSION pins an exact release instead of relying on the
# "stable" channel lookup at update.k3s.io, which has been returning 404s.
curl -sfL https://get.k3s.io | \
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
} >>/home/vagrant/.bashrc
