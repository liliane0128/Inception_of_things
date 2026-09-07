#!/usr/bin/env bash
set -eu

# Run by hand inside the VM (not wired as a Vagrant provisioner on purpose --
# during the defense the evaluator watches this install everything live):
#   vagrant ssh lilwangS
#   bash scripts/install.sh
#
# Installs Docker + kubectl + k3d, creates a k3d cluster with the app's port
# mapped out to the VM, then bootstraps Argo CD (namespaces, Argo CD itself,
# the argocd CLI, and the Application CR that starts the GitOps deploy).

CONFS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../confs" && pwd)"

echo "==> Installing Docker"
if ! command -v docker >/dev/null; then
	curl -fsSL https://get.docker.com | sudo sh
fi
# For future SSH sessions -- this script itself still uses sudo for every
# docker/k3d call below, since group membership only takes effect on
# re-login and isn't worth fighting with sg/newgrp mid-script.
sudo usermod -aG docker "$(whoami)"

echo "==> Installing kubectl"
if ! command -v kubectl >/dev/null; then
	KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
	curl -sLo /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
	sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
fi

echo "==> Installing k3d"
if ! command -v k3d >/dev/null; then
	curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | sudo bash
fi

# wil42/playground only publishes an amd64 image (single-platform manifest,
# confirmed with `docker manifest inspect`). This VM runs amd64 natively
# (VirtualBox on a Linux/amd64 host), so no QEMU/binfmt_misc emulation is
# needed here -- unlike the arm64-on-Apple-Silicon setup this was developed
# on originally, where `docker run --privileged tonistiigi/binfmt --install
# all` was required (and had to be re-run after every VM reboot, since it's
# kernel state). If you ever run this on an arm64 host again, re-add that
# step here.

echo "==> Creating k3d cluster (app port 8888 mapped out to the VM)"
if ! sudo k3d cluster list | grep -q '^iot '; then
	sudo k3d cluster create iot -p "8888:8888@loadbalancer" --wait
fi

# `sudo k3d` writes its kubeconfig for root, not for this user -- capture it
# via stdout instead of --kubeconfig-merge-default so it lands (with the
# right ownership) in this user's own ~/.kube/config.
mkdir -p "$HOME/.kube"
sudo k3d kubeconfig get iot >/tmp/iot-kubeconfig
sudo chown "$(id -u):$(id -g)" /tmp/iot-kubeconfig
mv /tmp/iot-kubeconfig "$HOME/.kube/config"
export KUBECONFIG="$HOME/.kube/config"

kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo "==> Creating namespaces"
kubectl apply -f "$CONFS_DIR/argocd-namespace.yaml" -f "$CONFS_DIR/dev-namespace.yaml"

echo "==> Installing Argo CD"
# --server-side: Argo CD's install manifest includes a large CRD
# (applicationsets.argoproj.io) whose full JSON no longer fits inside the
# 262144-byte annotation that client-side `kubectl apply` stores on every
# object (metadata.annotations: Too long). Server-side apply doesn't use
# that annotation at all, so it doesn't hit the limit.
kubectl apply -n argocd --server-side --force-conflicts \
	-f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd wait --for=condition=available --timeout=300s deployment/argocd-server deployment/argocd-repo-server

echo "==> Installing argocd CLI"
if ! command -v argocd >/dev/null; then
	ARGOCD_VERSION=$(curl -sL https://raw.githubusercontent.com/argoproj/argo-cd/stable/VERSION)
	curl -sSLo /tmp/argocd "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-amd64"
	sudo install -m 0755 /tmp/argocd /usr/local/bin/argocd
fi

echo "==> Applying the Argo CD Application (this starts the dev deploy)"
kubectl apply -f "$CONFS_DIR/application.yaml"

echo "==> Done. argocd initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
echo "UI: kubectl -n argocd port-forward svc/argocd-server 8080:443  (then https://localhost:8080)"
echo "App: curl http://localhost:8888/"
