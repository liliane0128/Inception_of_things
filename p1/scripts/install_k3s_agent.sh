#!/usr/bin/env bash
set -eu

IFACE=$(ip -4 -o addr show | awk -v ip="$NODE_IP" '$4 ~ "^"ip"/" {print $2; exit}')

curl -sfL https://get.k3s.io | K3S_URL="https://${SERVER_IP}:6443" K3S_TOKEN="$K3S_TOKEN" \
	INSTALL_K3S_EXEC="agent \
		--node-ip=${NODE_IP} \
		--flannel-iface=${IFACE}" \
	sh -
