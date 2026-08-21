# Inception-of-Things

K3s + Vagrant exercises, done in two steps: `p1` sets up a 2-node cluster,
`p2` runs 3 apps behind an Ingress on a single node.

## Provider note

Configured for **QEMU** (`vagrant-qemu` + `socket_vmnet`) since this is
being developed/tested on Apple Silicon, where VirtualBox's ARM64 support
is unreliable. On any other system, use **VirtualBox** instead: swap
`config.vm.box` for a standard box (e.g. `generic/ubuntu2204`), replace the
`provider "qemu"` block with `provider "virtualbox"` (`vb.memory`/`vb.cpus`),
and drop the `socket_vmnet` setup below — everything else (IPs, scripts,
tokens) stays the same.

## Host prerequisites (QEMU/macOS)

```bash
brew install qemu socket_vmnet
brew install --cask vagrant
vagrant plugin install vagrant-qemu
```

`socket_vmnet` must be running (as root, in its own terminal) before any
`vagrant up`:

```bash
sudo mkdir -p /opt/homebrew/var/run
sudo /opt/homebrew/opt/socket_vmnet/bin/socket_vmnet \
  --vmnet-gateway=192.168.56.1 \
  --vmnet-dhcp-end=192.168.56.100 \
  /opt/homebrew/var/run/socket_vmnet
```

---

## Part 1 — K3s and Vagrant

Two VMs: `lilwangS` (K3s server, `192.168.56.110`) and `lilwangSW` (K3s
agent, `192.168.56.111`), joined into one cluster.

```
p1/
├── Vagrantfile
└── scripts/
    ├── install_k3s_server.sh   # server node
    └── install_k3s_agent.sh    # agent node, joins the server
```

```bash
cd p1
vagrant up
vagrant ssh lilwangS -c "kubectl get nodes -o wide"
vagrant halt      # stop both VMs
vagrant destroy -f
```

## Part 2 — K3s and three simple applications

One VM: `lilwangS` (K3s server, `192.168.56.110`) running 3 nginx apps
behind an Ingress, routed by `Host` header (`app1.com`, `app2.com`,
anything else → `app3`). `app2` runs 3 replicas.

```
p2/
├── Vagrantfile
├── scripts/
│   ├── install_k3s.sh    # k3s server
│   └── deploy_apps.sh    # kubectl apply confs/
└── confs/
    ├── app1.yaml
    ├── app2.yaml
    ├── app3.yaml
    └── ingress.yaml
```

```bash
cd p2
vagrant up
vagrant ssh lilwangS -c "kubectl get all"
vagrant ssh lilwangS -c 'curl -H "Host: app1.com" 192.168.56.110'
vagrant ssh lilwangS -c 'curl -H "Host: app2.com" 192.168.56.110'
vagrant ssh lilwangS -c 'curl 192.168.56.110'   # default -> app3
vagrant halt
vagrant destroy -f
```
