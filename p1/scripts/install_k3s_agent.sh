#!/usr/bin/env bash
set -eu

# Find the NIC that owns NODE_IP (the private_network interface), so flannel
# uses that link instead of the NAT/default interface.
IFACE=$(ip -4 -o addr show | awk -v ip="$NODE_IP" '$4 ~ "^"ip"/" {print $2; exit}')

# Install k3s as an agent (worker) and join it to the server via K3S_URL,
# authenticating with the shared K3S_TOKEN.
# INSTALL_K3S_VERSION pins an exact release instead of relying on the
# "stable" channel lookup at update.k3s.io, which has been returning 404s.
# Must match the server's version.
curl -sfL https://get.k3s.io | K3S_URL="https://${SERVER_IP}:6443" K3S_TOKEN="$K3S_TOKEN" \
	INSTALL_K3S_VERSION="v1.36.3+k3s1" \
	INSTALL_K3S_EXEC="agent \
		--node-ip=${NODE_IP} \
		--flannel-iface=${IFACE}" \
	sh -
