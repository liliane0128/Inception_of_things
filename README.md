# Part 1 — K3s and Vagrant

Two VMs, one K3s cluster: a controller (`liliwangS`) and an agent
(`liliwangSW`), each on a dedicated static IP, provisioned entirely through
Vagrant.

## Architecture

```
                 Host (macOS, Apple Silicon)
                          |
              socket_vmnet daemon (192.168.56.0/24)
                 gateway .1, dhcp pool ends at .100
                          |
        +-----------------+-----------------+
        |                                   |
 liliwangS  (192.168.56.110)        liliwangSW  (192.168.56.111)
 K3s server (control-plane)         K3s agent (worker)
 1 vCPU / 1024 MB                   1 vCPU / 1024 MB
        |                                   |
        +------------- K3s API :6443 -------+
```

Each VM has **two network interfaces**:

- NIC 0 — QEMU user-mode NAT, used only for `vagrant ssh` (forwarded port,
  never touched directly).
- NIC 1 — the private network, statically configured via cloud-init to
  `192.168.56.110` / `.111`. This is the interface K3s actually binds and
  advertises on, so cluster traffic never crosses the NAT NIC.

The agent joins the server over `https://192.168.56.110:6443` using a
pre-shared token (`K3S_TOKEN` in the `Vagrantfile`), so there's no need to
fetch a token from the server after the fact.

## Why QEMU instead of VirtualBox

This host is Apple Silicon, where VirtualBox's ARM64 support is still
experimental and prone to breaking. The subject explicitly allows any
provider (*"You can use any tools you want to set up your host virtual
machine as well as the provider used in Vagrant"*), so this setup uses
[`vagrant-qemu`](https://github.com/ppggff/vagrant-qemu) — a Vagrant
provider built on QEMU, which has solid native support for Apple Silicon.

Static IPs and VM-to-VM/host-to-VM networking on macOS require a network
backend; this uses [`socket_vmnet`](https://github.com/lima-vm/socket_vmnet),
which holds the privileged `vmnet.framework` membership in a small daemon so
that `vagrant` itself never needs `sudo`.

## Prerequisites (host)

```bash
brew install qemu socket_vmnet
brew install --cask vagrant
vagrant plugin install vagrant-qemu
```

## One-time network setup

`socket_vmnet` needs to run as root, once, before any `vagrant up`. It stays
in the foreground, so give it its own terminal tab and leave it running:

```bash
sudo mkdir -p /opt/homebrew/var/run
sudo /opt/homebrew/opt/socket_vmnet/bin/socket_vmnet \
  --vmnet-gateway=192.168.56.1 \
  --vmnet-dhcp-end=192.168.56.100 \
  /opt/homebrew/var/run/socket_vmnet
```

The gateway/DHCP range is deliberately capped at `.100` so the static IPs
`.110`/`.111` never collide with a DHCP lease. Once this daemon is running,
every `vagrant` command below runs as your normal user — no `sudo` needed.

## Usage

```bash
cd p1
vagrant up                                    # brings up both VMs, in order
vagrant ssh liliwangS -c "kubectl get nodes -o wide"
vagrant ssh liliwangSW -c "hostname"
vagrant halt                                  # stop both VMs
vagrant destroy -f                            # tear down both VMs
```

Expected `kubectl get nodes -o wide` output once both machines are up:

```
NAME         STATUS   ROLES           VERSION        INTERNAL-IP
liliwangs    Ready    control-plane   v1.36.3+k3s1   192.168.56.110
liliwangsw   Ready    <none>          v1.36.3+k3s1   192.168.56.111
```

(Kubernetes lowercases node names; the actual VM/OS hostnames are
`liliwangS` and `liliwangSW`.)

## File structure

```
p1/
├── README.md
├── Vagrantfile
└── scripts/
    ├── install_k3s_server.sh   # controller: k3s in server mode
    └── install_k3s_agent.sh    # worker: k3s in agent mode, joins the server
```

Each provisioning script auto-detects its VM's private-network interface
(`ip -4 -o addr show`, matched against the IP passed in by the Vagrantfile)
and passes it to K3s via `--flannel-iface`, so cluster traffic stays off the
NAT interface regardless of what the guest OS happens to name its NICs.

`kubectl` is not installed separately — the official K3s install script
already creates a working `kubectl` (symlinked to the `k3s` binary, which
defaults to `/etc/rancher/k3s/k3s.yaml`), which satisfies the subject's
"install kubectl" requirement on its own.

## Troubleshooting

- **`vagrant up` hangs / times out waiting to boot**: rare, but on this host
  two HVF-accelerated aarch64 VMs starting close together can occasionally
  wedge one of them very early in boot (near-zero CPU usage, RSS stuck at a
  few MB). `vagrant destroy -f <name> && vagrant up <name>` reliably fixes
  it.
- **SSH/API calls fail after a fresh reboot of the host**: the
  `socket_vmnet` daemon doesn't survive a reboot unless you restart it —
  redo the one-time network setup step above.
- **Do not** overwrite `/usr/local/bin/kubectl` with a separately downloaded
  binary. K3s's installer leaves it as a symlink to the `k3s` binary itself;
  writing through that symlink (e.g. `curl -o /usr/local/bin/kubectl ...`)
  truncates the real `k3s` executable instead of just replacing the
  symlink, breaking the running cluster.
