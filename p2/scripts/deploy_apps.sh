#!/usr/bin/env bash
set -eu

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# k3s starts the API server asynchronously; wait for the node to report
# Ready before applying workloads on top of it.
until kubectl get nodes 2>/dev/null | grep -q " Ready"; do
	sleep 2
done

kubectl apply -f /home/vagrant/confs
