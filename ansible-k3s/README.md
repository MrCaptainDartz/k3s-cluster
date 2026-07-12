# HA K3s Cluster with Ansible

This project automates the deployment of a highly available (HA) K3s cluster using Ansible.

It includes the following elements out of the box:

- **3 Control Plane nodes** with embedded etcd for resilient data.
- **[kube-vip](https://kube-vip.io/)** to provide a virtual IP (VIP) to access the Kubernetes API server, running here in ARP mode.
- **[MetalLB](https://metallb.universe.tf/)** to provide IPs accessible on the local network for `LoadBalancer` type services.
- **Ceph CSI** to automatically connect the cluster to your existing Proxmox/Ceph distributed storage, providing persistent volumes via RBD and CephFS.

The deployment uses the highly popular Ansible role [ansible-role-k3s](https://github.com/PyratLabs/ansible-role-k3s).

## Prerequisites

- **Ansible >= 2.10** installed on the machine running the commands.
- **Python 3** with the `netaddr` package installed locally (`pip3 install netaddr`).
- Configured SSH key access to all your target servers/VMs (the playbook uses the `ubuntu` user by default, who has passwordless `sudo` rights).
- **Network reachability** from the K3s nodes to the Ceph monitor IPs (ports `3300` / `6789`). If the K3s network and the Ceph network are different VLANs/subnets, make sure they are routed and that no firewall (e.g. the Proxmox datacenter/node firewall) rejects the Ceph monitor ports.

## Preparing the Ceph cluster

The CSI driver connects to an **existing** Ceph cluster (e.g. a Proxmox Ceph). Before running Ansible, the following objects must exist on the Ceph side and their values reported in `inventory/group_vars/all.yml`. Run these commands from a machine that has the `ceph` CLI (a Proxmox node, or wherever your admin keyring is).

### 1. The RBD pool and CephFS filesystem must exist

```bash
ceph osd pool ls | grep pool1_ssd          # RBD pool used by the ceph-rbd StorageClass
ceph fs ls | grep cephfs1_ssd             # CephFS filesystem used by the ceph-cephfs StorageClass
ceph fs status cephfs1_ssd
```

Create them if missing (names must match `ceph_rbd_pool` and `cephfs_fs_name` in `all.yml`).

### 2. Get the real monitor addresses

```bash
ceph mon dump
```

Use the IPs from the `mon addr` column as `ceph_monitors` in `all.yml`. **Do not** guess them — wrong monitor IPs make provisioning hang with `context deadline exceeded`.

### 3. Create the dedicated Ceph user (RBD + CephFS caps)

Using a dedicated user (e.g. `k3s-ceph-dev`) rather than `client.admin` is strongly recommended. The CSI needs RBD caps (for the block driver) **and** CephFS caps (for the shared filesystem driver):

```bash
ceph auth get-or-create client.k3s-ceph-dev \
  mon "profile rbd, allow r" \
  mgr "profile rbd, allow rw" \
  osd "profile rbd pool=pool1_ssd, profile rbd pool=.mgr, allow rw pool=cephfs1_ssd_data, allow rw pool=cephfs1_ssd_metadata" \
  mds "allow rws path=/volumes/csi"
```

> The `pool1_ssd`, `cephfs1_ssd_data` and `cephfs1_ssd_metadata` names above are the **example values** (matching `all.yml.example`). Substitute your own: the RBD pool is `ceph_rbd_pool`, the CephFS data/metadata pool names are those reported by `ceph fs ls` for your filesystem (Proxmox names them `<fsname>_data` and `<fsname>_metadata` by default).

Cap breakdown:

| Daemon | Cap | Why |
| ------ | --- | --- |
| `mon` | `profile rbd, allow r` | RBD operations + read-only monitor access for CephFS metadata. |
| `mgr` | `profile rbd, allow rw` | RBD provisioning/metadata (`profile rbd`) + CephFS subvolume path/management via the manager `volumes` module (`allow rw`). Without `allow rw` the CephFS node plugin fails to mount with `does your client key have mgr caps?`. |
| `osd` | `profile rbd pool=pool1_ssd` | Read/write RBD images in the block pool. |
| `osd` | `profile rbd pool=.mgr` | RBD metadata stored in the `.mgr` pool. |
| `osd` | `allow rw pool=cephfs1_ssd_data` | Read/write CephFS file data. |
| `osd` | `allow rw pool=cephfs1_ssd_metadata` | Read/write CephFS metadata (omap, subvolumes). |
| `mds` | `allow rws path=/volumes/csi` | Create/manage subvolumes inside the `csi` subvolume group. |

Retrieve the secret key and put it in `all.yml` as `ceph_client_key`:

```bash
ceph auth print-key client.k3s-ceph-dev
```

> The user name (`k3s-ceph-dev`) goes into `ceph_client_id`, the key into `ceph_client_key`. The same credentials are used for both the RBD and the CephFS secrets.

### 4. Create the CephFS subvolume group

The CephFS driver places each PVC in a **subvolume group** (default name `csi`, configurable via `cephfs_subvolumegroup`). This group must exist on the Ceph side, otherwise PVC creation fails with `subvolume group 'csi' does not exist`:

```bash
ceph fs subvolumegroup create cephfs1_ssd csi
ceph fs subvolumegroup ls cephfs1_ssd        # → csi
```

The `mds` cap above (`allow rws path=/volumes/csi`) must match this group name: the subvolume group `csi` lives at `/volumes/csi` in the filesystem.

## Quick Start

### 1. Install the dependency role

Before starting, download the Ansible dependency:

```bash
cd ansible-k3s
ansible-galaxy install -r requirements.yml
```

### 2. Customize the configuration

Copy the provided example configuration files to adapt them to your infrastructure:

```bash
cp inventory/hosts.yml.example inventory/hosts.yml
cp inventory/group_vars/all.yml.example inventory/group_vars/all.yml
```

- **`inventory/hosts.yml`**: Add the actual IPs of your machines and their login credentials here.
- **`inventory/group_vars/all.yml`**: Adjust configuration variables such as the VIP address, MetalLB IP range, and your Ceph credentials.

> **Important**: Never commit `hosts.yml` and `all.yml` if they contain or will contain passwords (like `ceph_client_key`). The directory already uses `.gitignore` to prevent accidental leaks, but be careful.

#### Main variables (`all.yml`)

Here are some important variables based on the provided examples:

| Variable              | Example                                | Explanation                                                            |
| --------------------- | -------------------------------------- | ---------------------------------------------------------------------- |
| `k3s_release_version` | `stable`                               | K3s version to deploy (can be a specific release like `v1.31.2+k3s1`). |
| `k3s_etcd_snapshot_cron` | `0 */6 * * *`                        | Cron expression for scheduled etcd snapshots (embedded etcd only).   |
| `k3s_etcd_snapshot_retention` | `28`                         | Snapshots retained per control-plane node (≈ 7 days at 6 h intervals). |
| `k3s_vip`             | `192.168.1.10`                         | The target IP for kube-vip. This IP must be available on the network.  |
| `k3s_vip_interface`   | `{{ ansible_default_ipv4.interface }}` | On which network interface to share the VIP.                           |
| `metallb_ip_range`    | `192.168.1.150-192.168.1.199`          | The IP range dynamically assigned by MetalLB to your applications.     |
| `ceph_csi_operator_version` | `v1.0.4`                         | The [ceph-csi-operator](https://github.com/ceph/ceph-csi-operator) release deployed (CRDs, RBAC and operator manifests are pulled from this tag). |
| `ceph_client_id`      | `admin`                                | The Ceph user used by the CSI driver to authenticate storage requests. |
| `ceph_client_key`     | `YOUR-CEPH-KEYRING...`                 | The secret key that allows K3s to authenticate storage requests.       |
| `ceph_monitors`       | `['192.168.1.200', ...]`               | The IPs of the available Ceph monitors on the network.                 |
| `ceph_rbd_pool`       | `pool1_ssd`                            | The existing Ceph RBD pool backing the `ceph-rbd` StorageClass.        |
| `cephfs_fs_name`      | `cephfs1_ssd`                          | The existing CephFS filesystem backing the `ceph-cephfs` StorageClass. |
| `cephfs_subvolumegroup` | `csi`                                | The CephFS subvolume group used by the CephFS driver (must exist in Ceph). |
| `ceph_sc_rbd_name`    | `ceph-rbd`                             | Name of the RBD StorageClass (the `storageClassName` to reference in a PVC). |
| `ceph_sc_cephfs_name` | `ceph-cephfs`                          | Name of the CephFS StorageClass (the `storageClassName` to reference in a PVC). |

#### Tested component versions

The versions below are the ones currently pinned in `inventory/group_vars/all.yml` (the source of truth) and mirrored in `all.yml.example`. Keep them in sync when you bump a component, and re-test the cluster after any change.

| Component               | Variable                  | Version  |
| ----------------------- | ------------------------- | -------- |
| K3s (channel)           | `k3s_release_version`     | `stable` |
| kube-vip                | `kube_vip_version`        | `v1.2.1` |
| MetalLB                 | `metallb_version`         | `v0.16.1`|
| Ceph CSI Operator       | `ceph_csi_operator_version` | `v1.0.4`|

> K3s follows the `stable` channel, which is a moving target. For stricter reproducibility you may pin a specific release (e.g. `v1.31.2+k3s1`) instead.

### 3. Run the deployment

Simply run the playbook:

```bash
ansible-playbook -i inventory/hosts.yml site.yml
```

## Architecture

The generated architecture, based on the default dummy variables of the project (`all.yml.example` and `hosts.yml.example`), looks like this:

```mermaid
flowchart TD
    Client(["User / Admin"])

    subgraph VIP ["Virtual IP API"]
        KubeVIP("kube-vip: 192.168.1.10")
    end

    subgraph LoadBalancer ["MetalLB"]
        direction LR
        LBPool["Allocated IP range<br>192.168.1.150 - 192.168.1.199"]
    end

    Client -->|"kubectl / port 6443"| VIP
    Client -->|"Dynamic web traffic"| LoadBalancer

    VIP --> N1
    VIP --> N2
    VIP --> N3

    subgraph ClusterK3s ["K3s Cluster (Control Planes & etcd)"]
        direction LR
        N1["k3s-node-01<br>192.168.1.101"]
        N2["k3s-node-02<br>192.168.1.102"]
        N3["k3s-node-03<br>192.168.1.103"]
    end

    ClusterK3s -.- LoadBalancer

    subgraph CephStorage ["External Ceph Cluster"]
        direction LR
        Mon1["Monitor<br>192.168.1.200"]
        Mon2["Monitor<br>192.168.1.201"]
        Mon3["Monitor<br>192.168.1.202"]
        Data[("RBD & CephFS Shares")]
    end

    N1 -->|"Ceph CSI Driver"| CephStorage
    N2 -->|"Ceph CSI Driver"| CephStorage
    N3 -->|"Ceph CSI Driver"| CephStorage
```

## Project Structure

```
ansible-k3s/
├── ansible.cfg                          # Local Ansible settings
├── requirements.yml                     # Dependencies (the k3s role)
├── site.yml                             # The installation playbook
├── inventory/
│   ├── hosts.yml.example                # Blank inventory with your target nodes
│   └── group_vars/
│       └── all.yml.example              # Centralization of cluster variables
└── templates/
    ├── 01-kube-vip-rbac.yml.j2          # Manifest files injected by the role
    ├── 02-kube-vip-daemonset.yml.j2
    ├── 04-metallb-config.yml.j2
    ├── 05-ceph-secrets.yml.j2
    ├── 06-ceph-storageclasses.yml.j2
    ├── 10-ceph-csi-operator-config.yml.j2
    └── 11-network-policies.yml.j2        # Baseline NetworkPolicies (kube-router netpol)
```

## Backups (etcd snapshots)

K3s (with the embedded etcd datastore) takes automatic snapshots on **each control-plane node** on the schedule defined by `k3s_etcd_snapshot_cron` (default: every 6 hours) and keeps `k3s_etcd_snapshot_retention` of them (default: 28, ≈ 7 days at 6 h intervals). Snapshots are written to `/var/lib/rancher/k3s/server/db/snapshots/` on every server.

These settings are injected through the `k3s_server` config (`etcd-snapshot-schedule-cron` / `etcd-snapshot-retention`).

```bash
# List snapshots on a control-plane node
sudo k3s etcd-snapshot ls

# Trigger an ad-hoc snapshot
sudo k3s etcd-snapshot save

# Restore from a snapshot — requires stopping k3s on all servers first.
# See the K3s docs for the full procedure:
#   https://docs.k3s.io/datastore/backup-restore
sudo k3s etcd-snapshot snapshot ...
```

> Snapshots stay on the node by default. For off-node / off-site backup, point K3s at an S3 bucket (`etcd-s3-endpoint`, `etcd-s3-bucket`, …) or sync the snapshot directory elsewhere — out of scope for this homelab baseline.

## Network policies

K3s enforces Kubernetes `NetworkPolicy` resources **out of the box** via its embedded **kube-router network-policy controller**, which is active by default alongside the Flannel CNI. Disable it with `--disable-network-policy` only if you install a CNI that brings its own policy engine (Calico, Cilium, …).

No policies are applied by default, so the pod network is flat: every pod can reach every pod, across all namespaces. The auto-deployed manifest `11-network-policies.yml.j2` installs a conservative starter baseline that **denies all ingress** in three namespaces, while leaving egress open (so DNS resolution and normal outbound traffic keep working):

| Namespace                  | Policy            | Why                                                                                                 |
| -------------------------- | ----------------- | --------------------------------------------------------------------------------------------------- |
| `default`                  | deny all ingress  | Isolates workloads deployed in the default namespace; they can still initiate connections (DNS, egress) but cannot be reached from other pods/namespaces. |
| `ceph-csi-operator-system` | deny all ingress  | The CSI driver exposes no network endpoints to pods; deny inbound as defense-in-depth (this namespace holds the Ceph credentials Secret). |
| `metallb-system`           | deny all ingress  | MetalLB speakers announce via ARP/L2 and do not need inbound from workloads.                      |

This is the **cluster baseline** (system + quarantine namespaces): deny ingress, egress left open. **Application namespaces** use a stricter, state-of-the-art pattern — deny-all (ingress + egress) + explicit allows — applied per namespace; see [Securing a new namespace (step by step)](#securing-a-new-namespace-step-by-step).

What is **not** affected:

- **DNS** — pods still egress to `kube-dns` in `kube-system`, which has no ingress deny.
- **Probes** — kubelet liveness/readiness probes (node-to-pod traffic) are exempt from NetworkPolicy.
- **Egress** — all pods can still initiate outbound connections.

> **`hostNetwork` pods are not enforced.** kube-router (K3s's policy engine) intentionally skips pods running with `hostNetwork: true`, as does the upstream Kubernetes model. Concretely the **Ceph CSI node plugins** and the **MetalLB speakers** both run in `hostNetwork`, so the policies on `ceph-csi-operator-system` and `metallb-system` only really apply to the operator/controller pods (which is what we want to protect — they hold the Ceph Secret / manage allocations). Don't rely on these policies to isolate the speakers/plugins themselves: they share the node's network namespace.

> **North-south exposure is blocked by the `default` deny.** Any pod in `default` that is the backend of a `LoadBalancer`, `NodePort`, or `Ingress` Service will be **unreachable** until you add an allow policy. With MetalLB and the default `externalTrafficPolicy: Cluster`, kube-proxy SNATs the source to a node IP; with `externalTrafficPolicy: Local` the original client IP is preserved — in both cases the source is not in the allow-list, so the traffic is dropped. Same story for an ingress controller reaching services in `default`.

### Securing a new namespace (step by step)

A freshly created namespace has **no NetworkPolicy**, so the pod network is flat — every pod can reach every pod, across all namespaces. The state-of-the-art baseline is: **close everything, then re-open only what you need, in this order.** One namespace per application.

#### Step 1 — Create the namespace

```bash
kubectl create namespace my-app
```

#### Step 2 — Deny all (close the namespace)

Apply `default-deny-all`. From this point **no traffic enters or leaves** any pod in `my-app` — neither ingress nor egress, not even from other pods in the same namespace.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: my-app
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

#### Step 3 — Allow traffic within the namespace

Re-allow ingress and egress between pods of `my-app` (the app ↔ its database, sidecars, etc.).

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: my-app
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
  ingress:
    - from:
        - podSelector: {}     # pods in THIS namespace only — a podSelector
                              # without a namespaceSelector is scoped to my-app.
                              # (namespaceSelector: {} would mean ALL namespaces!)
  egress:
    - to:
        - podSelector: {}     # same: pods in THIS namespace only
```

#### Step 4 — Allow DNS

Mandatory: with egress denied (Step 2), pods can no longer resolve names, so re-allow egress to CoreDNS (`kube-dns` in `kube-system`, UDP/TCP 53).

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: my-app
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

**Steps 1–4 are the baseline**: the namespace is isolated, its pods talk to each other, and DNS works. Steps 5 and 6 are only needed if the app is exposed, or reaches outside.

> Tip: apply Steps 1–4 in one shot with `kubectl apply -f -` and the three documents separated by `---`.

#### Step 5 — (only if the app must be reached from outside) Allow ingress

> **Yes, you still need this with MetalLB.** MetalLB routes external traffic to your pods, but it does **not** bypass NetworkPolicy. The packet reaches the backend pod with its source rewritten — SNAT'd to a node IP with `externalTrafficPolicy: Cluster`, or the real client IP with `externalTrafficPolicy: Local` — and in both cases that source is not in the allow-list, so `default-deny-all` drops it. Allow it explicitly.

For a `LoadBalancer`/`NodePort` Service (MetalLB):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-lb-ingress
  namespace: my-app
spec:
  podSelector:
    matchLabels:
      app: my-app                      # narrow to your app's pods
  policyTypes: [Ingress]
  ingress:
    - from:
        - ipBlock:
            cidr: 192.168.1.0/24       # your node/L2 subnet (SNAT'd source); adapt
```

For an **ingress controller** (Layer 7) instead of a raw LoadBalancer, replace the `ipBlock` with a `namespaceSelector` on the controller's namespace, e.g. `kubernetes.io/metadata.name: ingress-nginx`. To preserve the real client IP on a `LoadBalancer`, set `externalTrafficPolicy: Local` on the Service and allow the **client CIDR** instead of the node subnet.

#### Step 6 — (only if the app must reach outside) Allow egress

With egress denied by `default-deny-all`, the app cannot reach the internet, the API server, or another namespace's services until you allow it. Example — internet egress for an app that calls external APIs:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-internet-egress
  namespace: my-app
spec:
  podSelector:
    matchLabels:
      app: my-app
  policyTypes: [Egress]
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0            # restrict to the destinations/ports you actually need
```

Other egress examples to adapt: allow TCP `6443` to the API server (VIP/nodes) for controllers that watch resources; allow TCP `3300`/`6789` to the monitor IPs for **direct** Ceph clients.

> Apps that consume Ceph **via PVCs** (RBD/CephFS) do **not** need egress to the monitors: the CSI node plugins run in `hostNetwork` and handle the mount from the node, outside NetworkPolicy. Only direct Ceph clients (librados, an S3 gateway, a CephFS client library) need a Ceph-egress allow.

> Put these per-namespace / per-app policies in your own Git repo or a K8s manifest directory — they are application-specific and do **not** belong in `templates/` (which holds the cluster baseline only).

## Verification

To check the health of the deployed component, you can run these queries:

```bash
# Retrieve the remote configuration file for kubectl
scp ubuntu@<A-NODE-IP>:/etc/rancher/k3s/k3s.yaml ~/.kube/config

# Update the server URL inside the config to use the VIP instead of 127.0.0.1
sed -i 's/127.0.0.1/YOUR_VIP_ADDRESS/' ~/.kube/config

# Check the presence of the servers
kubectl get nodes -o wide

# Diagnose the kube-vip interface
kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip-ds

# Verify MetalLB
kubectl get pods -n metallb-system

# Verify the Ceph storage configuration
kubectl get pods -n ceph-csi-operator-system
kubectl get cephconnection,clientprofile,driver -n ceph-csi-operator-system
kubectl get csidriver
kubectl get storageclass

# Verify the baseline NetworkPolicies
kubectl get networkpolicy -A

# Verify the etcd snapshot schedule (run on a control-plane node)
sudo k3s etcd-snapshot ls
```
