# Inception of Things

This project is part of 42's outer-circle curriculum, completed by lilwang and dbhujoo.

A 42 school project exploring Kubernetes fundamentals through three
progressively larger exercises, all run inside Vagrant managed VMs.
It starts with a bare two node K3s cluster, moves on to routing
several apps through a single Ingress, and ends with a GitOps setup
where Argo CD keeps a deployment in sync with a git repository, no
manual `kubectl` involved. A bonus part on top of Part 3 adds a
self hosted GitLab instance so the whole GitOps loop runs entirely
inside the cluster.

```
p1/      2 node K3s cluster
p2/      1 node K3s cluster, 3 apps behind an Ingress
p3/      K3d cluster with Argo CD doing GitOps
bonus/   self hosted GitLab, wired into Part 3's Argo CD setup
```

## Host prerequisites

VirtualBox and Vagrant are required. On a 42 school machine, sudo is
not available, so Vagrant has to be installed by hand as a portable
build.

```bash
wget https://releases.hashicorp.com/vagrant/2.4.9/vagrant_2.4.9_linux_amd64.zip
unzip vagrant_2.4.9_linux_amd64.zip
chmod +x vagrant
./vagrant --appimage-extract
mkdir -p ~/.local
mv squashfs-root ~/.local/vagrant
echo 'export PATH="$HOME/.local/vagrant/usr/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

Fedora 44 also drops `libcrypt.so.1`, which the bundled Ruby needs:

```bash
dnf download libxcrypt-compat
mkdir -p ~/libxcrypt-extract
cd ~/libxcrypt-extract
rpm2cpio ../libxcrypt-compat-4.5.2-3.fc44.x86_64.rpm | cpio -idmv
mkdir -p ~/.local/vagrant-libs
cp usr/lib64/libcrypt.so.1 ~/.local/vagrant-libs/
echo 'vagrant() { LD_LIBRARY_PATH="$HOME/.local/vagrant-libs:$LD_LIBRARY_PATH" "$HOME/.local/vagrant/usr/bin/vagrant" "$@"; }' >> ~/.bashrc
source ~/.bashrc
vagrant --version
```

---

## Part 1: K3s and Vagrant

Two VMs, `lilwangS` as the K3s server at `192.168.56.110` and
`lilwangSW` as the K3s agent at `192.168.56.111`, joined into one
cluster.

```
p1/
├── Vagrantfile
└── scripts/
    ├── install_k3s_server.sh
    └── install_k3s_agent.sh
```

```bash
cd p1
vagrant up
vagrant ssh lilwangS
# inside the VM:
kubectl get nodes -o wide

vagrant halt
vagrant destroy -f
```

## Part 2: K3s and three simple applications

One VM, `lilwangS` at `192.168.56.110`, running three nginx apps
behind an Ingress routed by `Host` header: `app1.com`, `app2.com`,
and anything else falling through to `app3`. `app2` runs three
replicas.

```
p2/
├── Vagrantfile
├── scripts/
│   ├── install_k3s.sh
│   └── deploy_apps.sh
└── confs/
    ├── app1.yaml
    ├── app2.yaml
    ├── app3.yaml
    └── ingress.yaml
```

```bash
cd p2
vagrant up
vagrant ssh lilwangS
# inside the VM:
kubectl get all
curl -H "Host: app1.com" 192.168.56.110
curl -H "Host: app2.com" 192.168.56.110
curl 192.168.56.110

vagrant halt
vagrant destroy -f
```

## Part 3: K3d and Argo CD

One VM, `lilwangS`. Instead of K3s installed directly on the VM,
this part runs a K3d cluster, K3s in Docker, with an Argo CD
instance inside it that continuously syncs an app from a separate
public GitHub repo,
[lilwang_iot](https://github.com/liliane0128/lilwang_iot). A change
pushed there is picked up automatically, no manual `kubectl` step
needed on the running pod.

Two namespaces: `argocd` for Argo CD itself, `dev` for the deployed
app, [wil42/playground](https://hub.docker.com/r/wil42/playground).

```
p3/
├── Vagrantfile
├── scripts/
│   └── install.sh       # run by hand inside the VM
└── confs/
    ├── argocd-namespace.yaml
    ├── dev-namespace.yaml
    └── application.yaml
```

The GitOps watched files, `deployment.yaml` and `service.yaml`,
live in `lilwang_iot`'s `manifests/` folder, not in this repo.

`install.sh` is deliberately not wired as a Vagrant provisioner, it
runs by hand so the install stays visible step by step instead of
hidden inside `vagrant up`.

```bash
cd p3
vagrant up
vagrant ssh lilwangS
# inside the VM:
bash scripts/install.sh
kubectl get ns                       # argocd, dev
kubectl get pods -n dev              # wil-playground pod Running
curl http://localhost:8888/          # {"status":"ok","message":"v1"}
```

To demonstrate the GitOps rollout, from the host, outside the VM,
inside a clone of `lilwang_iot`, not this repo:

```bash
sed -i 's/wil42\/playground:v1/wil42\/playground:v2/' manifests/deployment.yaml
git add manifests/deployment.yaml
git commit -m "roll out v2"
git push
```

Back inside the VM, wait for Argo CD's next sync, or force it with
`argocd app sync wil-playground` once logged in, then re-run the
`curl`. The response flips to `"message": "v2"` with no `kubectl`
command run by hand.

If it doesn't roll out after a few minutes, check the Application's
sync status before assuming the pod is stuck:

```bash
kubectl get application -n argocd wil-playground \
  -o jsonpath='{.status.sync.status}{"\n"}{.status.operationState.message}{"\n"}'
```

`OutOfSync` with an error message here, for example "server could
not find the requested resource", means the manifest itself is
invalid, Argo CD is retrying and failing rather than silently
ignoring the push. Fix the manifest, commit, push again.

```bash
vagrant halt
vagrant destroy -f
```