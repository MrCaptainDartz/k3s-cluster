# HA K3s Cluster with Ansible

A reproducible 3-node HA K3s homelab baseline — embedded etcd, kube-vip, MetalLB, Traefik, Ceph CSI, cert-manager, zero-trust NetworkPolicies, Pod Security Standards, and optional observability — deployed by one Ansible playbook. Built on the popular [ansible-role-k3s](https://github.com/PyratLabs/ansible-role-k3s) role.

## What's inside

Out of the box:

- **3 Control Plane nodes** with embedded etcd for resilient data.
- **[kube-vip](https://kube-vip.io/)** — virtual IP (VIP) for the Kubernetes API server, in ARP mode.
- **[MetalLB](https://metallb.universe.tf/)** — IPs accessible on the local network for `LoadBalancer` services.
- **[Traefik](https://traefik.io/)** — the K3s-packaged Ingress Controller, kept enabled and customized via a `HelmChartConfig`.
- **Ceph CSI** — connects the cluster to an existing Proxmox/Ceph distributed storage, providing persistent volumes via RBD and CephFS.
- **[cert-manager](https://cert-manager.io/)** (optional) — real TLS certificates from Let's Encrypt via DNS-01, with per-domain DNS-provider credentials (Cloudflare / OVH / Infomaniak) and a locked-down namespace.
- **Observability** (optional) — Prometheus + Grafana + Loki + Alloy + node-exporter.
- **Zero-trust NetworkPolicies** and **Pod Security Standards** baseline across the cluster.

### Project structure

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
    ├── 11-network-policies.yml.j2        # Baseline NetworkPolicies for default + metallb-system (kube-router netpol)
    ├── 12-traefik-config.yml.j2          # HelmChartConfig customizing the K3s-packaged Traefik
    ├── 13-pod-security.yml.j2            # Pod Security Standards: enforce=baseline on `default`
    ├── 22-certmanager-webhook-ovh.yml.j2  # HelmChart CR installing the OVH DNS-01 webhook (only if an OVH cred exists)
    ├── 23-certmanager-dns-secrets.yml.j2  # DNS provider credential Secrets (only if certmanager_enabled)
    ├── 24-certmanager-issuers.yml.j2     # Let's Encrypt ClusterIssuers, multi-provider DNS-01 (only if certmanager_enabled)
    ├── 25-certmanager-network-policies.yml.j2 # cert-manager namespace deny-all + explicit allows (only if certmanager_enabled)
    ├── 26-certmanager-webhook-secret-reader.yml.j2 # Role+RoleBinding letting OVH/Infomaniak webhooks read their cred Secrets (only if certmanager_enabled)
    ├── 34-nfs-storageclasses.yml.j2       # NFS CSI StorageClasses, one per nfs_shares entry (only if nfs_enabled)
    ├── 44-smb-storageclasses.yml.j2       # SMB CSI StorageClasses, one per smb_shares entry (only if smb_enabled)
    ├── 50-ceph-secrets.yml.j2            # Ceph client key Secret (always-on, group 50-56)
    ├── 51-ceph-storageclasses.yml.j2     # RBD (Delete default + Retain) + CephFS StorageClasses
    ├── 55-ceph-csi-operator-config.yml.j2 # Driver / CephConnection / ClientProfile CRs
    ├── 56-ceph-network-policies.yml.j2   # ceph-csi-operator-system deny-all + targeted egress
    ├── 60-kube-prometheus-stack.yml.j2   # HelmChart CR: Prometheus + Operator + Grafana + Alertmanager + kube-state-metrics (only if observability_enabled, node-exporter disabled)
    ├── 61-loki.yml.j2                    # HelmChart CR: Loki monolithic + filesystem PVC (only if observability_enabled)
    ├── 62-alloy.yml.j2                   # HelmChart CR: Alloy log shipper DaemonSet in observability-host (only if observability_enabled)
    ├── 63-node-exporter.yml.j2           # HelmChart CR: prometheus-node-exporter DaemonSet in observability-host (only if observability_enabled)
    ├── 64-observability-network-policies.yml.j2 # monitoring + observability-host deny-all + targeted allows (only if observability_enabled)
    └── 65-observability-rules.yml.j2     # ServiceMonitors/PodMonitors + platform PrometheusRule (only if observability_enabled)
```

> The `.j2` files above are rendered by the role; the **URL** manifests (MetalLB native, ceph-csi-operator CRD/RBAC/operator, the NFS/SMB driver manifests, `cert-manager.yaml`, the Infomaniak webhook) are downloaded directly into the same `/var/lib/rancher/k3s/server/manifests/` dir. They all share one numbering scheme with **no overlap between ranges**, applied in filename order:
>
> | Range   | Component | Source |
> | ------- | --------- | ------ |
> | `01-13` | baseline (kube-vip, MetalLB, network policies, Traefik, Pod Security) | templates + URLs |
> | `20-26` | cert-manager (cert-manager + Infomaniak/OVH webhooks + DNS secrets/issuers/NPs) | URLs 20-21 + templates 22-26 |
> | `30-34` | NFS CSI (RBAC/driverinfo/controller/node + StorageClasses) | URLs 30-33 + template 34 |
> | `40-44` | SMB CSI (RBAC/driver/controller/node + StorageClasses) | URLs 40-43 + template 44 |
> | `50-56` | Ceph CSI (secrets, StorageClasses, operator CRD/RBAC/deploy, config, NP) | URLs 52-54 + templates 50,51,55,56 |
> | `60-65` | Observability (kube-prometheus-stack + Loki + Alloy + node-exporter, all HelmChart CRs) | templates 60-65 |
>
> Within each range the driver/CRDs precede the StorageClasses/policies that depend on them. cert-manager sits right after the baseline; the three CSI drivers (NFS/SMB/Ceph) are grouped together after it; observability is last. Ceph is the always-on primary storage (no `*_enabled` flag); NFS/SMB/cert-manager/observability are opt-in.

## Quick start

### Prerequisites

- **Ansible >= 2.10** installed on the machine running the commands.
- **Python 3** with the `netaddr` package installed locally (`pip3 install netaddr`).
- Configured SSH key access to all your target servers/VMs (the playbook uses the `ubuntu` user by default, who has passwordless `sudo` rights).
- **Network reachability** from the K3s nodes to the Ceph monitor IPs (ports `3300` / `6789`). If the K3s network and the Ceph network are different VLANs/subnets, make sure they are routed and that no firewall (e.g. the Proxmox datacenter/node firewall) rejects the Ceph monitor ports.

### 1. Install the dependency role

Before starting, download the Ansible dependency:

```bash
cd ansible-k3s
ansible-galaxy install -r requirements.yml
```

### 2. Prepare the Ceph cluster

The CSI driver connects to an **existing** Ceph cluster (e.g. a Proxmox Ceph). Before running Ansible, the following objects must exist on the Ceph side and their values reported in `inventory/group_vars/all.yml`. Run these commands from a machine that has the `ceph` CLI (a Proxmox node, or wherever your admin keyring is).

#### 2.1 The RBD pool and CephFS filesystem must exist

```bash
ceph osd pool ls | grep pool1_ssd          # RBD pool used by the ceph-rbd StorageClass
ceph fs ls | grep cephfs1_ssd             # CephFS filesystem used by the ceph-cephfs StorageClass
ceph fs status cephfs1_ssd
```

Create them if missing (names must match `ceph_rbd_pool` and `cephfs_fs_name` in `all.yml`).

#### 2.2 Get the real monitor addresses

```bash
ceph mon dump
```

Use the IPs from the `mon addr` column as `ceph_monitors` in `all.yml`. **Do not** guess them — wrong monitor IPs make provisioning hang with `context deadline exceeded`.

#### 2.3 Create the dedicated Ceph user (RBD + CephFS caps)

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

#### 2.4 Create the CephFS subvolume group

The CephFS driver places each PVC in a **subvolume group** (default name `csi`, configurable via `cephfs_subvolumegroup`). This group must exist on the Ceph side, otherwise PVC creation fails with `subvolume group 'csi' does not exist`:

```bash
ceph fs subvolumegroup create cephfs1_ssd csi
ceph fs subvolumegroup ls cephfs1_ssd        # → csi
```

The `mds` cap above (`allow rws path=/volumes/csi`) must match this group name: the subvolume group `csi` lives at `/volumes/csi` in the filesystem.

### 3. Customize the configuration

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
| `k3s_release_version` | `v1.36.2+k3s1`                         | Pinned K3s release (not the `stable` channel, which silently bumps Traefik's chart and breaks the HelmChartConfig). Bump deliberately and re-test. |
| `k3s_etcd_snapshot_cron` | `0 */6 * * *`                        | Cron expression for scheduled etcd snapshots (embedded etcd only).   |
| `k3s_etcd_snapshot_retention` | `28`                         | Snapshots retained per control-plane node (≈ 7 days at 6 h intervals). |
| `coredns_replicas`    | `3`                                    | CoreDNS replica count, re-asserted by a `post_tasks` step (no K3s flag exists; K3s v1.25.5+ doesn't pin replicas so the scale persists). `topologySpreadConstraints` spread pods one-per-node → HA. See "CoreDNS high availability". |
| `k3s_vip`             | `192.168.1.10`                         | The target IP for kube-vip. This IP must be available on the network.  |
| `k3s_vip_interface`   | `` (empty = auto)                     | Interface announcing the VIP. Empty -> auto-resolved by a `pre_task` to the interface whose subnet matches `node_cidr` (multi-NIC safe — does not rely on the default-route interface). Set a name explicitly to override. |
| `node_cidr`           | `192.168.1.0/24`                       | Node-network CIDR (control planes + workers); used by the cert-manager NetworkPolicy (apiserver ingress/API egress). |
| `metallb_ip_range`    | `192.168.1.150-192.168.1.199`          | The IP range dynamically assigned by MetalLB to your applications.     |
| `traefik_lb_ip`       | `192.168.1.199`                        | Fixed MetalLB IP pinned to Traefik's LoadBalancer Service (must be within `metallb_ip_range`). |
| `ceph_csi_operator_version` | `v1.0.4`                         | The [ceph-csi-operator](https://github.com/ceph/ceph-csi-operator) release deployed (CRDs, RBAC and operator manifests are pulled from this tag). |
| `ceph_client_id`      | `admin`                                | The Ceph user used by the CSI driver to authenticate storage requests. |
| `ceph_client_key`     | `YOUR-CEPH-KEYRING...`                 | The secret key that allows K3s to authenticate storage requests.       |
| `ceph_monitors`       | `['192.168.1.200', ...]`               | The IPs of the available Ceph monitors on the network.                 |
| `ceph_rbd_pool`       | `pool1_ssd`                            | The existing Ceph RBD pool backing the `ceph-rbd` StorageClass.        |
| `cephfs_fs_name`      | `cephfs1_ssd`                          | The existing CephFS filesystem backing the `ceph-cephfs` StorageClass. |
| `certmanager_enabled` | `false`                               | Deploy cert-manager + Let's Encrypt issuers (DNS-01). When `false`, nothing is installed and Traefik keeps its self-signed cert. |
| `certmanager_version` | `v1.21.0`                             | [cert-manager](https://cert-manager.io/docs/installation/) release (official `cert-manager.yaml` pulled from this tag). |
| `certmanager_acme_email` | `you@example.com`                  | Email registered with Let's Encrypt (expiry notices). |
| `certmanager_acme_servers` | `[staging, prod]`                 | ACME endpoints → one `ClusterIssuer` each (staging = tests, prod = real). |
| `certmanager_dns_credentials` | `[…]`                            | Per-provider DNS creds (Cloudflare/OVH/Infomaniak), each routed by `match_domains`; tokens are **vault-protected**. See `all.yml.example`. |
| `certmanager_webhook_group_ovh` | `acme.myhomelab.example`        | OVH webhook `groupName` (must match the issuer); unique to you. |
| `cephfs_subvolumegroup` | `csi`                                | The CephFS subvolume group used by the CephFS driver (must exist in Ceph). |
| `ceph_sc_rbd_name`    | `ceph-rbd`                             | RBD StorageClass, the cluster **default** (`reclaimPolicy: Delete` — fine for reproducible/throwaway state such as the observability PVCs; dangerous for data you can't regenerate). |
| `ceph_sc_rbd_retain_name` | `ceph-rbd-retain`                 | RBD StorageClass, **opt-in** (`reclaimPolicy: Retain`) for important app data (DBs, anything non-reproducible). Pick the SC by **data value**, not storage type — the default is destructive. |
| `ceph_sc_cephfs_name` | `ceph-cephfs`                          | CephFS StorageClass (`reclaimPolicy: Retain` — the subvolume survives an accidental PVC deletion; clean up orphaned subvolumes manually). |
| `nfs_enabled`         | `false`                                | Deploy the NFS CSI driver + one StorageClass per entry in `nfs_shares`. `false` = nothing is installed. |
| `nfs_csi_version`     | `v4.13.4`                              | Release tag of `kubernetes-csi/csi-driver-nfs` (raw manifests pulled from this tag). |
| `nfs_shares`          | `[{name, server, share}]`              | One StorageClass per share (cluster-scoped, named after the share); `name` is the `storageClassName` to reference in a PVC. |
| `smb_enabled`         | `false`                                | Deploy the SMB CSI driver + one StorageClass per entry in `smb_shares`. `false` = nothing is installed. |
| `smb_csi_version`     | `v1.20.3`                              | Release tag of `kubernetes-csi/csi-driver-smb` (raw manifests pulled from this tag). |
| `smb_shares`          | `[{name, source}]`                     | One StorageClass per share (cluster-scoped, named after the share); `name` is the `storageClassName` to reference in a PVC. |
| `smb_secret_name`     | `csi-smb-creds`                        | Name of the credentials Secret you create **per namespace** (the StorageClasses resolve it via `${pvc.namespace}`). |
| `observability_enabled` | `false`                            | Deploy the monitoring baseline (kube-prometheus-stack + Loki + Alloy + node-exporter). `false` = nothing is installed. See [Observability (optional)](#observability-optional). |
| `observability_prometheus_retention` / `_storage` | `15d` / `20Gi`        | Prometheus retention window and PVC size (on `ceph-rbd`). ~50k series at 30s scrape → ~6-10GB for 15d; 20Gi leaves headroom. |
| `observability_loki_retention` / `_storage` | `7d` / `10Gi`             | Loki compactor retention and PVC size (filesystem storage on `ceph-rbd`). |
| `observability_scrape_interval` | `30s`                          | Scrape interval applied to the ServiceMonitors in `65-`. |
| `observability_grafana_hostname` | `grafana.example.com`       | Hostname for the Grafana Ingress (Traefik). TLS is added when `certmanager_enabled`. |
| `observability_grafana_tls_issuer` | `letsencrypt-prod`         | cert-manager `ClusterIssuer` used for the Grafana Ingress TLS (must match a `certmanager_acme_servers` entry). |
| `observability_alertmanager_telegram_bot_token` / `_chat_id` | `REDACTED` / `0` | Alertmanager Telegram receiver (native `telegram_configs`). **Secrets** — real values in the gitignored `all.yml`; `chat_id` is an integer (negative for groups). |
| `observability_grafana_admin_password` | `REDACTED`                  | Grafana initial admin password. **Secret** — real value in the gitignored `all.yml`; change it after first login. |

#### Tested component versions

The versions below are the ones currently pinned in `inventory/group_vars/all.yml` (the source of truth) and mirrored in `all.yml.example`. Keep them in sync when you bump a component, and re-test the cluster after any change.

| Component               | Variable                  | Version  |
| ----------------------- | ------------------------- | -------- |
| K3s (pinned)            | `k3s_release_version`     | `v1.36.2+k3s1` |
| kube-vip                | `kube_vip_version`        | `v1.2.1` |
| MetalLB                 | `metallb_version`         | `v0.16.1`|
| Traefik (packaged with K3s) | follows `k3s_release_version` | Traefik **v3** on K3s v1.32+ (chart v39); v2 on v1.31 and earlier |
| Ceph CSI Operator       | `ceph_csi_operator_version` | `v1.0.4`|
| NFS CSI (optional)      | `nfs_csi_version`         | `v4.13.4`|
| SMB CSI (optional)      | `smb_csi_version`         | `v1.20.3`|
| cert-manager (optional) | `certmanager_version`     | `v1.21.0`|
| OVH DNS webhook (optional) | `certmanager_webhook_ovh_chart_version` | `0.9.14` (aureq chart) |
| Infomaniak DNS webhook (optional) | `certmanager_webhook_infomaniak_version` | `v0.3.1` |
| kube-prometheus-stack (optional) | `observability_kps_chart_version` | `87.15.1` |
| Loki (optional) | `observability_loki_chart_version` | `18.4.4` (community chart) |
| Alloy (optional) | `observability_alloy_chart_version` | `1.10.1` |
| prometheus-node-exporter (optional) | `observability_node_exporter_chart_version` | `4.56.0` |

> K3s is **pinned** to a specific release (`v1.36.2+k3s1`) rather than the moving `stable` channel, so a K3s bump (which silently changes the bundled Traefik chart version) is a deliberate, tested change.

### 4. Optional NAS storage (NFS & SMB CSI)

For bulk data (photos, films, backups) on a **NAS**, you can optionally deploy the [NFS](https://github.com/kubernetes-csi/csi-driver-nfs) and/or [SMB](https://github.com/kubernetes-csi/csi-driver-smb) CSI drivers. Both are **disabled by default**; set the flag to `true`, list the shares you need, then rerun the playbook. When a flag is `false`, nothing is installed. Each entry in `nfs_shares` / `smb_shares` produces **one StorageClass** (cluster-scoped, named after the share), so different apps can use different shares — the app just picks the right `storageClassName`.

```yaml
# all.yml
nfs_enabled: true
nfs_shares:
  - name: nfs-media          # StorageClass name -> storageClassName in a PVC
    server: nas.example.com
    share: /export/media
  - name: nfs-backup
    server: nas2.example.com
    share: /export/backup
    mount_options: [nfsvers=4.1, ro]   # optional, overrides nfs_mount_options

smb_enabled: true
smb_shares:
  - name: smb-photos
    source: "//nas.example.com/photos"
  - name: smb-movies
    source: "//nas.example.com/movies"
```

Reference the StorageClass explicitly in a PVC (none of them is the cluster default — Ceph RBD is):

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: photos
  namespace: my-app
spec:
  accessModes: ["ReadWriteMany"]
  storageClassName: smb-photos      # or nfs-media, smb-movies, ...
  resources:
    requests:
      storage: 100Gi
```

#### SMB credentials — isolated per namespace

The SMB StorageClasses resolve their credentials Secret in the **PVC's own namespace** via the CSI `${pvc.namespace}` token, so credentials are isolated per application. This baseline **does not** create that Secret (the namespaces are created later by you); you create it in **each namespace that consumes an SMB share**, when you set up that application. Put it alongside your app manifests and vault-protect it — it no longer lives in the cluster `all.yml`.

```yaml
# e.g. my-app/smb-creds.yaml (one per consuming namespace)
apiVersion: v1
kind: Secret
metadata:
  name: csi-smb-creds              # must match smb_secret_name in all.yml
  namespace: my-app
type: Opaque
stringData:
  username: "USER"
  password: "PASS"
  domain: ""                       # omit or leave empty if no domain/workgroup
```

```bash
kubectl apply -f my-app/smb-creds.yaml
# or imperatively:
kubectl -n my-app create secret generic csi-smb-creds \
  --from-literal username=USER --from-literal password=PASS --from-literal domain=""
```

> NFS needs no credentials, so no Secret is required for the NFS StorageClasses.

Notes:

- **No host install** for SMB: the node plugin bundles `cifs-utils` (only the `cifs` kernel module is needed on the host; Kerberos would need host `cifs-utils`, not configured here).
- The CSI **node plugin** is privileged/`hostNetwork` (like the Ceph plugin), but your **application** pods consuming the PVC are unprivileged — they just see a mounted filesystem.

### 5. Run the deployment

Simply run the playbook:

```bash
ansible-playbook -i inventory/hosts.yml site.yml
```

## Deploy an application (state of the art)

A freshly created namespace has **no NetworkPolicy**, so the pod network is flat — every pod can reach every pod, across all namespaces. The state-of-the-art baseline is: **close everything, then re-open only what you need, in this order.** One namespace per application.

### Step 1 — Create the namespace

Create the namespace **with `enforce=baseline`** so a misconfigured or compromised pod cannot escalate to `privileged` / `hostPath` / `hostNetwork` (mirrors the cluster `default` baseline — see [Pod Security Standards](#pod-security-standards-pss)). `baseline` lets ~95 % of normal pods through unchanged; it only blocks the genuine escape vectors.

```bash
kubectl create namespace my-app
kubectl label namespace my-app \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/enforce-version=latest
```

> If your app genuinely needs a baseline-violating pod (a CSI-style helper, a node exporter with `hostNetwork`), prefer putting that specific pod in a dedicated **exempt** namespace labelled `pod-security.kubernetes.io/enforce=privileged` (or `pod-security.kubernetes.io/exempt: true`), rather than weakening the app namespace. Most apps never need this.

### Step 2 — Deny all (close the namespace)

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

### Step 3 — Allow traffic within the namespace

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

> **Step 3 is a coarse allow** — every pod in `my-app` can reach every other pod in `my-app`. That is fine for a single-tier app. For a multi-tier app (frontend → backend → database) prefer **micro-segmentation by label**: narrow each tier's allow to exactly the tiers that may talk to it, instead of opening the whole namespace.

### Step 3b — (optional) Micro-segmentation by label

Replace the broad `allow-same-namespace` (Step 3) with per-tier least-privilege allows. Label your pods (e.g. `tier: frontend|backend|db`) and chain the allows so each tier admits only its upstream.

```yaml
# frontend admits only the ingress controller (see Step 5); nothing inside reaches it.
# backend admits frontend (ingress + egress), reaches db (egress).
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-admits-frontend
  namespace: my-app
spec:
  podSelector:
    matchLabels: { tier: backend }
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector:
            matchLabels: { tier: frontend }
      ports:
        - protocol: TCP
          port: 8080
---
# db admits backend only — frontend can never reach the database directly.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-admits-backend
  namespace: my-app
spec:
  podSelector:
    matchLabels: { tier: db }
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector:
            matchLabels: { tier: backend }
      ports:
        - protocol: TCP
          port: 5432
---
# backend egress to db (the only cross-tier outbound it needs; DNS is Step 4).
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-egress-to-db
  namespace: my-app
spec:
  podSelector:
    matchLabels: { tier: backend }
  policyTypes: [Egress]
  egress:
    - to:
        - podSelector:
            matchLabels: { tier: db }
      ports:
        - protocol: TCP
          port: 5432
```

A bare `podSelector` inside `from`/`to` (no `namespaceSelector`) is scoped to the **same namespace** as the policy — exactly what micro-segmentation needs. Add a `namespaceSelector: {}` by mistake and it becomes "all namespaces".

### Step 4 — Allow DNS

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

### Step 5 — (only if the app must be reached from outside) Allow ingress

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

For an **ingress controller** (Layer 7) instead of a raw LoadBalancer — e.g. the packaged **Traefik** in `kube-system` — replace the `ipBlock` with a `namespaceSelector` on `kube-system` combined with a `podSelector` on `app.kubernetes.io/name=traefik`, so only Traefik's pods can reach the backend:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-traefik-ingress
  namespace: my-app
spec:
  podSelector:
    matchLabels:
      app: my-app
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              app.kubernetes.io/name: traefik
      ports:
        - protocol: TCP
          port: 8080                  # the port your app Service listens on
```

> A `namespaceSelector` and a `podSelector` in the **same** `from` entry are AND-ed: the source pod must be in `kube-system` **and** match the Traefik label. To preserve the real client IP on a `LoadBalancer` (no ingress controller), set `externalTrafficPolicy: Local` on the Service and allow the **client CIDR** instead of the node subnet.

> **Traefik reaches my app — do I need a broad "allow Traefik to talk to everyone" policy?** No, and you can't really write one anyway: NetworkPolicy is **namespace-scoped**, so there is no single cluster-wide "Traefik may reach any pod" object — a policy in `my-app` can only select pods in `my-app`. The narrow per-app allow above (`namespaceSelector: kube-system` + the Traefik `podSelector`, AND-ed, on the exact port) is both the only place to express it and the safer choice: Traefik can reach **only** the pods you label and only on the port you name. A broader allow (e.g. `podSelector: {}` so any pod in `my-app` accepts Traefik) would let Traefik — and therefore any external HTTP client routing through it — touch every pod in the namespace, not just the one you meant to expose. Keep the allow tight to the exposed tier and port.

### Step 6 — (only if the app must reach outside) Allow egress

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

### Putting it together — a complete example

A single namespace secured end-to-end: a web app deployed, exposed through the packaged Traefik, with the policy set applied. Adapt the names/labels/ports to your app. Save as `my-app.yaml` and `kubectl apply -f my-app.yaml`.

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: my-app
  labels: { app: my-app }
spec:
  replicas: 2
  selector: { matchLabels: { app: my-app } }
  template:
    metadata:
      labels: { app: my-app }     # this label is what the Traefik allow matches
    spec:
      containers:
        - name: web
          image: nginxinc/nginx-unprivileged
          ports: [{ containerPort: 8080 }]
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: my-app
spec:
  selector: { app: my-app }
  ports: [{ port: 8080, targetPort: 8080 }]
---
# 1. Close the namespace: no traffic in or out unless explicitly allowed.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny-all, namespace: my-app }
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
# 2. DNS: re-allow egress to kube-dns (mandatory whenever egress is denied).
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-dns-egress, namespace: my-app }
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels: { kubernetes.io/metadata.name: kube-system }
          podSelector:
            matchLabels: { k8s-app: kube-dns }
      ports:
        - { protocol: UDP, port: 53 }
        - { protocol: TCP, port: 53 }
---
# 3. Let only the packaged Traefik (kube-system) reach the app, on :8080.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-traefik-ingress, namespace: my-app }
spec:
  podSelector: { matchLabels: { app: my-app } }
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels: { kubernetes.io/metadata.name: kube-system }
          podSelector:
            matchLabels: { app.kubernetes.io/name: traefik }
      ports:
        - { protocol: TCP, port: 8080 }
---
# 4. (optional) If the app calls external APIs, allow internet egress on the ports it needs.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-internet-egress, namespace: my-app }
spec:
  podSelector: { matchLabels: { app: my-app } }
  policyTypes: [Egress]
  egress:
    - to:
        - ipBlock: { cidr: 0.0.0.0/0 }      # narrow to the destinations/ports you actually use
      ports:
        - { protocol: TCP, port: 443 }
```

Then expose it through Traefik with an `Ingress` (the ClusterIssuers from cert-manager give you real TLS once you point `tls.secretName` at a Certificate):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
  namespace: my-app
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging   # or letsencrypt-prod
spec:
  ingressClassName: traefik
  tls:
    - hosts: ["my-app.captaindartz.org"]
      secretName: my-app-tls
  rules:
    - host: my-app.captaindartz.org
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port: { number: 8080 }
```

> Put these per-namespace / per-app policies in your own Git repo or a K8s manifest directory — they are application-specific and do **not** belong in `templates/` (which holds the cluster baseline only).

### Namespace & Pod Security

Create a dedicated namespace per application — never deploy workloads in `default` (it is a strict quarantine namespace). Label the namespace with Pod Security Standards: `enforce=baseline` for most apps, `enforce=restricted` for stricter ones, and leave it unlabelled (`enforce=privileged` or `pod-security.kubernetes.io/exempt: true`) only for pods that need `hostNetwork`/`hostPath` (e.g. a node exporter). See the [PSS table](#pod-security-standards-pss) for the cluster defaults.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Expose metrics for your app (ServiceMonitor)

Prometheus already discovers ServiceMonitors across all namespaces: the platform Prometheus in `60-` uses **nil selectors** (`serviceMonitorSelector: {}` + `serviceMonitorSelectorNilUsesHelmValues: false`), so a `ServiceMonitor` in your app's namespace is picked up automatically — no label needed. Just declare a `ServiceMonitor` selecting your app's `Service` by a named `metrics` port.

Because your app namespace is zero-trust (deny-all both ways), Prometheus cannot reach the metrics port until you allow it. Add an `allow-ingress-from-prometheus` NetworkPolicy on the metrics port — the same pattern used for the locked-down system namespaces (`metallb-system` / `cert-manager` / `ceph-csi-operator-system`) in `11-` / `25-` / `56-`: allow ingress **from** the `monitoring` namespace, pod `app.kubernetes.io/name: prometheus`, on the metrics port.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: my-app          # or `monitoring`; nil selectors pick it up either way
spec:
  selector:
    matchLabels:
      app: my-app            # selects your app's Service
  endpoints:
    - port: metrics          # named port on the Service (see below)
      path: /metrics
      interval: 30s
```

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: my-app
  labels: { app: my-app }
spec:
  selector: { app: my-app }
  ports:
    - name: http
      port: 8080
      targetPort: 8080
    - name: metrics          # the ServiceMonitor's `port: metrics` resolves to this name
      port: 8080
      targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-from-prometheus
  namespace: my-app
spec:
  podSelector:
    matchLabels:
      app: my-app
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
          podSelector:
            matchLabels:
              app.kubernetes.io/name: prometheus
      ports:
        - protocol: TCP
          port: 8080          # must match the `metrics` port above
```

## Architecture

The default dummy variables (`all.yml.example` and `hosts.yml.example`) produce this topology:

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

- **Control-plane HA**: 3 nodes run embedded etcd + the kube API server; kube-vip holds the VIP (`k3s_vip`) in ARP mode, so `kubectl` targets one stable IP that floats to a healthy server.
- **LoadBalancer**: MetalLB (`metallb_ip_range`) hands IPs to `LoadBalancer` Services; Traefik is pinned to `traefik_lb_ip`.

### CoreDNS high availability

K3s ships CoreDNS as a managed Addon. Since v1.25.5 (PR #6552) the packaged `coredns` manifest carries **no `spec.replicas`**, and there is **no server flag** to set the count (unlike `etcd-snapshot-schedule-cron`). Two consequences:

- A manual `kubectl scale deploy coredns -n kube-system --replicas=N` **persists** across k3s restarts — the addon controller doesn't reset it.
- The Deployment's built-in `topologySpreadConstraints` (`maxSkew: 1`, `DoNotSchedule` on `kubernetes.io/hostname`) spread the pods **one per node**, so `N = 3` (your node count) survives any single node loss with **zero DNS gap**.

To make this durable and reproducible, the count is driven by the `coredns_replicas` variable (default `3` in `all.yml`) and **re-asserted on every `ansible-playbook site.yml` run** by a `post_tasks` step that scales the Deployment on the first control plane. Verify after a deploy:

```bash
kubectl get deploy -n kube-system coredns        # READY 3/3
kubectl get pod -n kube-system -l k8s-app=kube-dns -o wide   # one per node
```

## Backups (etcd snapshots)

K3s (embedded etcd datastore) takes automatic snapshots on **each control-plane node** on the schedule defined by `k3s_etcd_snapshot_cron` (default: every 6 hours) and keeps `k3s_etcd_snapshot_retention` of them (default: 28, ≈ 7 days at 6 h intervals). Snapshots are written to `/var/lib/rancher/k3s/server/db/snapshots/` on every server. These settings are injected through the `k3s_server` config (`etcd-snapshot-schedule-cron` / `etcd-snapshot-retention`).

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

## Optional components

### Traefik (Ingress)

K3s ships [Traefik](https://traefik.io/) as a packaged Ingress Controller — this project **keeps it enabled** and customizes it via a `HelmChartConfig` (`templates/12-traefik-config.yml.j2`), the supported way to overlay values on the bundled `traefik` HelmChart (K3s rewrites `traefik.yaml` on startup, so don't edit it). Version follows your K3s release: **Traefik v3 on K3s v1.32+** (chart v39), v2 on v1.31 and earlier.

The config only overrides what differs from the chart defaults:

- `deployment.kind: DaemonSet` — one Traefik per node (HA). The chart (Traefik v3 / chart v39+) reads `deployment.kind`, **not** a top-level `kind` — a top-level `kind: DaemonSet` is a silent no-op and leaves a single-replica Deployment.
- control-plane tolerations — so the DaemonSet lands on the control planes.
- `globalArguments: []` — drops the anonymous version-check / usage-report calls.
- HTTP → HTTPS redirect (`web` 80 → `websecure` 443).
- dashboard IngressRoute **on** + its `traefik` entryPoint (container port 8080) **exposed on the LB** — reachable at `http://<LB-IP>:8080/dashboard/`.
- fixed MetalLB IP via the `metallb.io/loadBalancerIPs` annotation (`traefik_lb_ip`).

Everything else uses chart defaults: both providers (`Ingress` + `IngressRoute`), `websecure` TLS **on** (Traefik serves its **self-signed default cert** when no cert resolver is configured — browsers warn), `service.type: LoadBalancer`, access logs **off**. Point your DNS at `traefik_lb_ip` and create `Ingress`/`IngressRoute` resources.

**TLS**: Traefik serves its **self-signed default cert** until you enable the optional **cert-manager** below (Let's Encrypt DNS-01) and annotate your Ingress.

**Dashboard**: the chart convenience IngressRoute has no host and no auth. It is bound to the internal `traefik` entryPoint (container port 8080), which the HelmChartConfig exposes on the LoadBalancer — so it's reachable at `http://<traefik_lb_ip>:8080/dashboard/` from anything that can hit the LB (HTTP, not HTTPS; it's a separate port from `web`/`websecure`, so the 80→443 redirect doesn't apply). Fine on a LAN; if you expose the cluster beyond it, drop `ports.traefik.expose` and instead bind the dashboard to a host behind TLS + basic-auth/IP-allow via your own `IngressRoute`.

**NetworkPolicy**: Traefik runs in `kube-system` (no deny there) but forwards to app namespaces under `default-deny-all` — allow ingress from Traefik's pods, see [Step 5](#step-5--only-if-the-app-must-be-reached-from-outside-allow-ingress).

### cert-manager (TLS) — optional

Off by default (`certmanager_enabled: false`): nothing is installed and Traefik keeps its self-signed default cert — fine for tests. Flip the flag to deploy [cert-manager](https://cert-manager.io/) plus two Let's Encrypt `ClusterIssuer`s (staging + prod) using **DNS-01** challenges.

Each `certmanager_dns_credentials` entry → one Secret (in `cert-manager`, vault-protected in `all.yml`) + one `dns01` solver inside every `ClusterIssuer`, routed by `match_domains` (fed to `selector.dnsZones`, so the apex, the wildcard **and** any concrete subdomain of a listed zone all solve — issue a wildcard cert now, per-subdomain certs later with no ansible change). Provider-specific:

| Provider | Credentials (in `all.yml`) | Webhook |
| --- | --- | --- |
| Cloudflare | `token` | built-in |
| OVH | `application_key` / `application_secret` / `consumer_key` + `endpoint` | [aureq chart](https://github.com/aureq/cert-manager-webhook-ovh), only if an OVH cred exists |
| Infomaniak | `token` | [official manifest](https://github.com/Infomaniak/cert-manager-webhook-infomaniak), only if an Infomaniak cred exists |

**Issue a cert** — annotate the Ingress:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod   # or letsencrypt-staging for tests
spec:
  tls:
    - hosts: ["app.example.tld"]
      secretName: app-example-tls
```

`hosts` can be the apex, a wildcard (`*.example.tld`), or any concrete subdomain of a `match_domains` zone — all are solved by the `dnsZones` selector. A common pattern is one wildcard cert reused across subdomains. Renewal is automatic (~30 days before expiry). The `cert-manager` namespace is locked down (deny-all both ways + explicit allows; no other namespace is touched).

### Observability — optional

Off by default (`observability_enabled: false`): nothing is installed. Flip the flag to deploy a monitoring baseline that lets you **see and alert on the platform itself** — nodes, kubelet/cAdvisor, kube-api, CoreDNS, Traefik, kube-vip, cert-manager, MetalLB, ceph-csi-operator — plus **pod logs**, with room to grow when your apps arrive.

#### Stack

Everything deploys via the project's **HelmChart CR** pattern, group `60-65`, opt-in via `observability_enabled`:

| Component | Chart | What it gives you |
| --- | --- | --- |
| [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) | `kube-prometheus-stack` (`60-`) | Prometheus + Prometheus Operator + Grafana + Alertmanager + kube-state-metrics + the Operator CRDs (ServiceMonitor/PodMonitor/PrometheusRule) + the upstream default dashboards and alert rules. **node-exporter is disabled here** and installed separately. |
| [Loki](https://github.com/grafana-community/helm-charts/tree/main/charts/loki) | `loki` (`61-`, community chart) | Logs backend, monolithic / single-binary, filesystem storage on a `ceph-rbd` PVC. |
| [Alloy](https://github.com/grafana/alloy/tree/main/operations/helm/charts/alloy) | `alloy` (`62-`) | Log shipper DaemonSet — tails pod logs from the node filesystem and pushes to Loki. (Metrics/traces collectors not declared; add them later.) |
| [prometheus-node-exporter](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-node-exporter) | `prometheus-node-exporter` (`63-`) | Host metrics (CPU/mem/disk/net) DaemonSet. Installed separately so it can live in the exempt namespace. |

kube-prometheus-stack **bundles its own ServiceMonitors** for kubelet / kube-apiserver / CoreDNS / kube-state-metrics, so those scrape automatically. `65-` adds the cross-namespace ServiceMonitors/PodMonitors for the components KPS does **not** cover (Traefik, kube-vip, cert-manager, MetalLB, ceph-csi-operator, our separate node-exporter) + one `PrometheusRule` with platform alerts (cert-manager certificates, PVC pending, crash-loop, disk full).

> **Backend is Prometheus** (not VictoriaMetrics). Storage: Prometheus ~20Gi + Loki ~10Gi + Grafana 5Gi, all on `ceph-rbd`. Retention: Prometheus 15d, Loki 7d (compactor). Tune `observability_prometheus_*` / `observability_loki_*` in `all.yml`.

#### Namespace split (PSA)

The control plane and the host-accessing collectors cannot share a namespace — node-exporter (`hostNetwork`+`hostPID`+`hostPath`) and Alloy (`hostPath /var/log/pods`) both violate PSA `baseline`. Split:

- **`monitoring`** — `enforce: baseline`. The stateful control plane (Prometheus, Grafana, Loki, Alertmanager, kube-state-metrics), all plain pods. Pre-created with labels by `13-pod-security.yml.j2`, then patched by the HelmCharts. Egress is **left open** (Prometheus is a privileged observer — like `kube-system`, it must reach kube-apiserver, kubelet and every target across namespaces); ingress is deny-all + Traefik→Grafana `:3000`, Alloy→Loki `:3100`, and intra-namespace self-scrape.
- **`observability-host`** — **unlabelled (exempt)**. The two host DaemonSets. Egress constrained to Loki `:3100` + DNS.

The locked-down system namespaces (`metallb-system`, `cert-manager`, `ceph-csi-operator-system`) each gain a gated `allow-ingress-from-prometheus` (in `11-`/`25-`/`56-`) so Prometheus can scrape their metrics ports — they stay deny-all for everyone but the scraper.

#### Enable it

```yaml
# inventory/group_vars/all.yml (gitignored — holds the secrets)
observability_enabled: true
observability_grafana_hostname: "grafana.yourdomain.tld"   # covered by a cert-manager DNS cred -> real TLS
observability_grafana_tls_issuer: "letsencrypt-prod"       # only used when certmanager_enabled
observability_alertmanager_telegram_bot_token: "123456:ABC..."   # from @BotFather
observability_alertmanager_telegram_chat_id: -1001234567890       # numeric; negative for groups
observability_grafana_admin_password: "change-me-after-first-login"
```

`observability_alertmanager_telegram_bot_token` and `observability_grafana_admin_password` are **secrets** — put them in the gitignored `all.yml`, never in the committed `all.yml.example` (same boundary as `ceph_client_key` / cert-manager DNS creds). Alerts go to Telegram via Alertmanager's native `telegram_configs` (no bridge component needed). The alert set: `CertManagerCertNotReady`, `CertManagerCertExpiringSoon` (<30d), `KubePersistentVolumeClaimPending`, `PodCrashLooping`, `NodeFilesystemAlmostFull` — complementing KPS's own comprehensive default ruleset.

#### CRD timing caveat

`65-` (ServiceMonitors/PodMonitors/PrometheusRule) needs the Prometheus Operator CRDs that `60-` installs. K3s auto-deploy is **fire-and-forget in filename order**, so on a **fresh deploy** these apply before the CRDs exist and are skipped; they apply cleanly on the **2nd boot** (the same caveat cert-manager issuers already live with). The `site.yml` post-tasks verify the pods are up; the scrape targets simply appear after a re-run. Verify with the commands in [Verification](#verification).

#### Verify the targets

The ServiceMonitors in `65-` use best-effort port names/labels for each platform component. After enabling, open **Prometheus → Status → Targets**: every target should be UP. A DOWN target means the `port`/`targetPort` or selector does not match the actual chart/manifest — adjust it in `65-` and the matching `allow-ingress-from-prometheus` port in `11-`/`25-`/`56-` (they must match the same pod port). Known likely adjustments: Traefik (requires the metrics entrypoint enabled — set it in `12-traefik-config.yml.j2`) and ceph-csi-operator (verify the operator's metrics bind port).

### NFS & SMB CSI

The [NFS](https://github.com/kubernetes-csi/csi-driver-nfs) and [SMB](https://github.com/kubernetes-csi/csi-driver-smb) CSI drivers are **disabled by default** and configured in deploy order — see [Quick start → Optional NAS storage](#4-optional-nas-storage-nfs--smb-csi) for the enable flags, the per-share StorageClasses, the PVC example and the per-namespace SMB credentials Secret.

Gotchas:

- **No host install** for SMB: the node plugin bundles `cifs-utils` (only the `cifs` kernel module is needed on the host; Kerberos would need host `cifs-utils`, not configured here).
- The CSI **node plugin** is privileged/`hostNetwork` (like the Ceph plugin), but your **application** pods consuming the PVC are unprivileged — they just see a mounted filesystem.

## Pod Security Standards (PSS)

The auto-deployed manifest `13-pod-security.yml.j2` enforces Kubernetes **Pod Security Standards** (the label-based admission control that replaced PodSecurityPolicy in v1.25), complementing the network zero-trust baseline.

| Namespace | `enforce` | `audit` / `warn` | Effect |
| --------- | --------- | ---------------- | ------ |
| `default` | `baseline` | `restricted` | Rejects privileged / `hostPath` / `hostNetwork` / `hostPID` / all-capabilities pods; logs+warns (does **not** block) pods that could be hardened to `restricted`. `default` is the strict-quarantine namespace (no real app belongs here), so `baseline` breaks nothing while closing escape vectors. |
| `cert-manager` (when enabled) | `baseline` | `restricted` | Same hardening: cert-manager's pods (controller/webhook/cainjector + the OVH webhook) are all plain pods (no `privileged`/`hostNetwork`/`hostPath`), so `baseline` breaks nothing and adds defense-in-depth on a namespace that already has a deny-all NetworkPolicy. |
| `cert-manager-infomaniak` (when an Infomaniak cred exists) | `baseline` | `restricted` | Same: the Infomaniak webhook runs here (separate namespace, created by its rendered-manifest); it is a plain pod, so `baseline` is safe. Pre-created with labels by `13-`, then patched by `21-`. |
| `monitoring` (when observability enabled) | `baseline` | `restricted` | The stateful observability control plane (Prometheus, Grafana, Loki, Alertmanager, kube-state-metrics) — all plain pods, so `baseline` breaks nothing and adds defense-in-depth. Pre-created with labels by `13-`, then patched by the kube-prometheus-stack / Loki HelmCharts (`60-`/`61-`). |
| `kube-system`, `metallb-system`, `ceph-csi-operator-system`, `observability-host` (when enabled) | — (unlabelled) | — | **Intentionally exempt**: these hold system pods that legitimately need `privileged`/`hostNetwork` (kube-vip, Traefik, MetalLB speakers, CSI node plugins). `observability-host` holds the host DaemonSets — node-exporter (`hostNetwork`+`hostPID`+`hostPath`) and Alloy (`hostPath /var/log/pods`) — which violate baseline and so are isolated in their own exempt namespace instead of weakening `monitoring`. K3s sets no cluster-wide default profile, so unlabelled = no enforcement. |

`restricted` is **not** enforced anywhere automatically — too many images do not comply (`runAsNonRoot`, `seccomp=RuntimeDefault`) and it would turn the baseline into friction. Opt into it **per sensitive namespace** when you create one.

**Application namespaces**: create them with `enforce=baseline` so a misconfigured/compromised app pod cannot escalate to `hostPath`/`privileged`. See [Step 1 of "Securing a new namespace"](#step-1--create-the-namespace).

Verify after a deploy:

```bash
kubectl get --show-labels ns default | grep -o 'pod-security.kubernetes.io/[^,]*'
# pod-security.kubernetes.io/audit=restricted
# pod-security.kubernetes.io/enforce=baseline
# pod-security.kubernetes.io/warn=restricted
# (a pod trying privileged in `default` is now rejected:)
kubectl -n default run pss-test --image=busybox --privileged --restart=Never -- true   # Error: ... privileged
```

## Network policies

No policies are applied by default, so the pod network is flat: every pod can reach every pod, across all namespaces. The auto-deployed manifest `11-network-policies.yml.j2` installs a **zero-trust** cluster baseline: **deny all ingress AND egress** in two namespaces (`default`, `metallb-system`), then re-open only the minimal egress each system component needs. The Ceph operator namespace (`ceph-csi-operator-system`) gets the same treatment from `56-ceph-network-policies.yml.j2`. `kube-system` deliberately gets **no policy** (its critical components — CoreDNS, kube-proxy, metrics-server, Traefik, kube-vip — need broad connectivity and run partly `hostNetwork`; locking it down on K3s is risky and out of scope).

| Namespace                  | Ingress      | Egress re-opened                                                                                                   | Why                                                                                                        |
| -------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| `default` (strict quarantine) | deny all  | DNS :53 (UDP/TCP) to `kube-dns` only                                                                              | A pod landing in `default` can resolve names but nothing else — cannot be reached, cannot phone home. Deploy real apps in a dedicated namespace, not `default`. |
| `metallb-system`           | deny all     | API `node_cidr:6443`, DNS :53                                                                                      | The controller does leader-election + watch via the API server. Speakers run `hostNetwork` (not enforced); the webhook is served to the kube-apiserver (node-origin, exempt — see below). |
| `ceph-csi-operator-system` (`56-`) | deny all     | Ceph `ceph_subnet` on 3300 / 6789 / 6800-7300 (`endPort`), API `node_cidr:6443`, DNS :53                            | The CSI provisioner connects to the Ceph monitors AND the OSDs directly (after fetching the OSD map), so egress targets the whole Ceph subnet. Protects the operator + ctrlplugin (hold the Ceph Secret / drive provisioning). |
| `kube-system`              | **none**     | —                                                                                                                  | Left open by design (critical components; partly `hostNetwork`). See note above.                           |

| `monitoring` (`64-`, when observability enabled) | deny all (ingress) | **egress left open** (privileged observer, like `kube-system`) | Prometheus must reach kube-apiserver, kubelet and every scraped target across namespaces, so egress is unconstrained. Ingress exceptions: Traefik → Grafana `:3000`, Alloy → Loki `:3100`, and intra-namespace self-scrape. |
| `observability-host` (`64-`, when observability enabled) | deny all (ingress) | Loki `:3100` (to `monitoring`), DNS :53 | Holds the host DaemonSets. Alloy only needs to push logs to Loki and resolve DNS; node-exporter is scraped (no egress). |

> **When observability is enabled**, the locked-down system namespaces (`metallb-system` in `11-`, `cert-manager` in `25-`, `ceph-csi-operator-system` in `56-`) each gain a gated `allow-ingress-from-prometheus` policy (under `{% if observability_enabled %}`) so the Prometheus pod in `monitoring` can reach their metrics ports (`:7473`, `:9402`, `:8081` respectively). The namespaces stay deny-all for everyone but Prometheus — only the scraper gets in.

This is the **cluster baseline** (system + quarantine namespaces): deny-all-both + targeted egress. **Application namespaces** use the same deny-all + explicit-allow pattern, applied per namespace; see [Deploy an application (state of the art)](#deploy-an-application-state-of-the-art).

What is **not** affected / **not** enforced:

- **DNS** — pods in the guarded namespaces reach `kube-dns` because DNS egress is explicitly re-opened above; `kube-system` itself has no deny, so CoreDNS keeps serving.
- **Probes** — kubelet liveness/readiness probes (node-to-pod traffic) are exempt from NetworkPolicy; node-originated traffic is not enforced.
- **Admission webhooks** — the cert-manager and MetalLB validating webhooks are called by the kube-apiserver, which runs as a host process (not a pod). That traffic is node-originated and therefore exempt, so the deny-ingress above does **not** break webhook validation (no separate ingress allow needed for the webhook itself).
- **`hostNetwork` pods** — kube-router intentionally skips pods running with `hostNetwork: true`, as does the upstream Kubernetes model. The **Ceph CSI node plugins** and the **MetalLB speakers** both run in `hostNetwork`, so the policies on `ceph-csi-operator-system` and `metallb-system` only really apply to the operator/controller/provisioner pods (which is what we want to protect). Don't rely on these policies to isolate the speakers/plugins themselves: they share the node's network namespace.

> **North-south exposure is blocked by the `default` deny.** Any pod in `default` that is the backend of a `LoadBalancer`, `NodePort`, or `Ingress` Service will be **unreachable** until you add an allow policy. With MetalLB and the default `externalTrafficPolicy: Cluster`, kube-proxy SNATs the source to a node IP; with `externalTrafficPolicy: Local` the original client IP is preserved — in both cases the source is not in the allow-list, so the traffic is dropped. Same story for an ingress controller reaching services in `default`. (`default` being a strict quarantine, you normally deploy apps in a dedicated namespace instead — see the tutorial.)

> **kube-router limitations** (K3s's policy engine, with Flannel): `endPort` (port ranges) **is supported** — used here for the Ceph OSD range 6800-7300; **FQDN** egress (e.g. `to: example.com`) is **not supported** — that is an API limitation of standard `networking.k8s.io/v1` NetworkPolicy, not kube-router, so use `ipBlock`/CIDR instead; **`hostNetwork` pods** are **not enforced** (see above). Keep these in mind when writing per-namespace policies.

## Verification

`site.yml` already **fails fast on a broken deploy**: `post_tasks` on the first control plane wait for the key platform components to roll out — Traefik (DaemonSet), the MetalLB controller, the ceph-csi-operator, cert-manager (when enabled) and the NFS/SMB controllers (when enabled). A manifest that fails to apply or a pod that never becomes Ready now fails the playbook instead of reporting success. The commands below are for manual, deeper checks after a successful run.

```bash
# Retrieve the remote kubeconfig for kubectl
scp ubuntu@<A-NODE-IP>:/etc/rancher/k3s/k3s.yaml ~/.kube/config

# Point the config at the VIP instead of 127.0.0.1
sed -i 's/127.0.0.1/YOUR_VIP_ADDRESS/' ~/.kube/config

# Check the nodes
kubectl get nodes -o wide

# Diagnose kube-vip
kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip-ds

# Verify MetalLB
kubectl get pods -n metallb-system

# Verify Traefik (K3s-packaged Ingress Controller) and its HelmChartConfig
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
kubectl get svc -n kube-system traefik               # LoadBalancer, EXTERNAL-IP == traefik_lb_ip, exposes 80/443/8080
kubectl get helmchartconfig -n kube-system traefik   # our values overlay
kubectl get ingressclass                             # traefik should be present
curl -s -o /dev/null -w '%{http_code}\n' http://<traefik_lb_ip>:8080/dashboard/   # 200 = dashboard reachable (unauthenticated, LAN)

# Verify the Ceph storage configuration
kubectl get pods -n ceph-csi-operator-system
kubectl get cephconnection,clientprofile,driver -n ceph-csi-operator-system
kubectl get csidriver
kubectl get storageclass

# Verify the optional NFS / SMB CSI drivers (only if nfs_enabled / smb_enabled)
kubectl get pods -n kube-system -l app.kubernetes.io/name=csi-nfs-controller   # NFS controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=csi-smb-controller   # SMB controller
kubectl get csidriver nfs.csi.k8s.io smb.csi.k8s.io
kubectl get storageclass | grep -E 'nfs-|smb-'                                 # one SC per share

# Verify the baseline NetworkPolicies (zero-trust cluster baseline)
kubectl get networkpolicy -A
# default: default-deny-all + allow-dns-egress | metallb-system: default-deny-all + allow-egress-kubeapi + allow-egress-dns
# ceph-csi-operator-system: default-deny-all + allow-egress-ceph + allow-egress-kubeapi + allow-egress-dns | cert-manager (if enabled): default-deny-all + 4 allows | kube-system: (intentionally none)
# Quick quarantine check — a pod in `default` resolves DNS but CANNOT reach outside:
kubectl run np-qc --rm -i --restart=Never --image=registry.k8s.io/e2e-test-images/jessie-dind:1.0 -- nslookup kubernetes.default   # resolves (DNS allowed)
kubectl run np-qc --rm -i --restart=Never --image=registry.k8s.io/e2e-test-images/jessie-dind:1.0 -- wget -T3 -qO- https://1.1.1.1 2>&1 | head   # FAILS (quarantine)

# Verify Pod Security Standards on `default` (enforce=baseline; a privileged pod is rejected)
kubectl get --show-labels ns default | grep -o 'pod-security.kubernetes.io/[^,]*'
# and on cert-manager when enabled (cert-manager-infomaniak only when an Infomaniak cred exists):
kubectl get --show-labels ns cert-manager cert-manager-infomaniak 2>/dev/null | grep -o 'pod-security.kubernetes.io/[^,]*'

# Verify cert-manager (only if certmanager_enabled)
kubectl get pods -n cert-manager
kubectl get clusterissuer                          # letsencrypt-staging / letsencrypt-prod, READY=True once ACME registers
kubectl get helmchart -n kube-system cert-manager-webhook-ovh   # only if an OVH cred exists
kubectl get role,rolebinding -n cert-manager | grep cred-reader  # webhook secret-reader RBAC (only if OVH/Infomaniak creds exist)
kubectl get networkpolicy -n cert-manager           # default-deny-all + the 4 explicit allows
# Confirm the API egress target matches the NP (endpoints within node_cidr):
kubectl get endpoints -n default kubernetes -o wide

# Verify observability (only if observability_enabled)
kubectl -n monitoring get all                            # prometheus, grafana, alertmanager, kube-state-metrics, loki Running
kubectl -n observability-host get ds                     # prometheus-node-exporter + alloy DaemonSets Ready (one pod per node)
kubectl get helmchart -n kube-system                      # kube-prometheus-stack, loki, alloy, prometheus-node-exporter
kubectl get networkpolicy -n monitoring                  # default-deny-all + allow-ingress-grafana/-from-alloy/-intra-namespace
kubectl get networkpolicy -n observability-host          # default-deny-all + allow-egress-to-loki + allow-egress-dns
# The scrape-ingress allows added to the locked-down namespaces (only when enabled):
kubectl get networkpolicy -n metallb-system            allow-ingress-from-prometheus
kubectl get networkpolicy -n cert-manager               allow-ingress-from-prometheus   # only if certmanager_enabled too
kubectl get networkpolicy -n ceph-csi-operator-system  allow-ingress-from-prometheus
# CRD-timing note: ServiceMonitors/PodMonitors/PrometheusRule (65-) need the Operator CRDs from kube-prometheus-stack (60-);
# on a fresh deploy they apply on the 2nd boot, so they may be absent right after the first run — re-run the playbook to apply them.
kubectl get servicemonitor,podmonitor,prometheusrule -n monitoring
# Open Grafana at https://<observability_grafana_hostname> (TLS valid when cert-manager on), log in with admin / <observability_grafana_admin_password>.
# In Prometheus -> Status -> Targets, every platform target should be UP; if one is DOWN its ServiceMonitor port name or label
# does not match the chart/manifest — adjust the `port`/`targetPort` in 65- and the matching allow port in 11/25/56.
# Grafana Logs explorer should show pod logs (Alloy -> Loki).

# Verify the etcd snapshot schedule (run on a control-plane node)
sudo k3s etcd-snapshot ls
```