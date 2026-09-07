# Inception-of-Things

K3s + Vagrant exercises, done in three steps: `p1` sets up a 2-node cluster,
`p2` runs 3 apps behind an Ingress on a single node, `p3` swaps K3s for K3d
and adds Argo CD for GitOps-style deployment.


## Host prerequisites (Linux/VirtualBox)

```bash
# Debian/Ubuntu — adjust for your distro if different
sudo apt update
sudo apt install -y virtualbox
sudo apt install -y vagrant   # or: https://developer.hashicorp.com/vagrant/install
```

No extra networking setup needed — VirtualBox's `private_network` works
out of the box, unlike the QEMU/`socket_vmnet` setup the Mac version
required.

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

## Part 3 — K3d and Argo CD

One VM: `lilwangS`. Instead of K3s installed directly on the VM, this part
runs a **K3d** cluster (K3s-in-Docker) and an **Argo CD** instance inside it
that continuously syncs an app from a separate public GitHub repo,
[lilwang_iot](https://github.com/liliane0128/lilwang_iot) — change a file
there, push, and the running pod updates itself with no manual `kubectl`
involved. It's a separate repo (not a subfolder of this one) specifically
so its *name* carries the group login, per the subject's requirement.

Two namespaces: `argocd` (Argo CD itself) and `dev` (the deployed app,
[wil42/playground](https://hub.docker.com/r/wil42/playground)).

```
p3/
├── Vagrantfile          # boots the VM only — no auto shell provisioner
├── scripts/
│   └── install.sh       # run BY HAND inside the VM: Docker, kubectl, k3d,
│                         # the k3d cluster, Argo CD, and the Application
└── confs/                # bootstrap manifests applied once by install.sh
    ├── argocd-namespace.yaml
    ├── dev-namespace.yaml
    └── application.yaml  # the Argo CD Application CR -- points at the
                           # lilwang_iot repo, path manifests
```

The actual GitOps-watched files (`deployment.yaml`, `service.yaml`) live in
[lilwang_iot](https://github.com/liliane0128/lilwang_iot)'s `manifests/`
folder, not in this repo.

`install.sh` is deliberately **not** wired as a Vagrant provisioner — it's
meant to be run by hand (e.g. during a defense) so the install is visible
step by step, not hidden inside `vagrant up`.

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

(No `binfmt`/QEMU-emulation step needed here: `wil42/playground` is an
amd64-only image, and this VM runs amd64 natively on VirtualBox — that
step only applied to the earlier arm64-on-Apple-Silicon dev setup, where it
also had to be re-run after every VM reboot since it's kernel state. Not a
concern on this Linux/VirtualBox setup.)

To demonstrate the GitOps rollout (from the host, outside the VM, inside a
clone of **lilwang_iot** — not this repo):

```bash
sed -i 's/wil42\/playground:v1/wil42\/playground:v2/' manifests/deployment.yaml
git add manifests/deployment.yaml
git commit -m "roll out v2"
git push
```

Use `sed` targeting the exact `image:` string above, or if editing by hand,
only touch the `image:` line — **not** the `apiVersion: apps/v1` line right
under the file's header comment. They both contain "v1" but are unrelated:
`apiVersion` is the Kubernetes API group version (only `apps/v1` is valid
for a Deployment) and bumping it to `apps/v2` breaks the sync instead of
rolling out anything.

Then back inside the VM, wait for Argo CD's next sync (or force it with
`argocd app sync wil-playground` once logged in) and re-run the `curl` —
the response flips to `"message": "v2"` with no `kubectl` command run by
hand.

If it doesn't roll out after a few minutes, check the Application's sync
status before assuming the pod is stuck:

```bash
kubectl get application -n argocd wil-playground \
  -o jsonpath='{.status.sync.status}{"\n"}{.status.operationState.message}{"\n"}'
```

`OutOfSync` + an error message here (e.g. "server could not find the
requested resource") means the manifest itself is invalid — Argo CD is
retrying and failing, not silently ignoring the push. Fix the manifest,
commit, push again.

```bash
vagrant halt
vagrant destroy -f
```
