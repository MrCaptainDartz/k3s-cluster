# GitOps layer (ArgoCD)

This directory is the **desired state** of the cluster's add-on stack. Once Ansible has bootstrapped
K3s + ArgoCD and registered the cluster against OpenBao (see [`../ansible-k3s/`](../ansible-k3s/)),
ArgoCD continuously synchronizes everything under `gitops/`.

This README is a **quick start for adapting the repo to your own environment** (different domain,
DNS provider, Ceph cluster, NAS shares, observability, etc.).

---

## How it is wired

```
gitops/
├── components/cluster-settings/                 # Shared Kustomize component (repo URL + branch)
├── bootstrap/
│   └── apps/                                    # App-of-apps: one Application per add-on (rendered by Kustomize)
└── infrastructure/                              # The actual manifests of each add-on
    ├── ceph-csi/  cert-manager/  external-dns/  external-secrets/  external-snapshotter/
    └── kured/  nfs-csi/  observability/  smb-csi/
```

- The Ansible template `11-root-app.yml.j2` creates the **root `Application`** that points ArgoCD at
  `gitops/bootstrap/apps/`.
- That path has a `kustomization.yaml` → ArgoCD renders it via **Kustomize** and creates one
  `Application` per add-on (app-of-apps pattern).
- Each `Application` points to its own `gitops/infrastructure/<app>/` directory, also rendered by
  Kustomize (helm charts + raw manifests).
- **Secrets** live as `kind: ExternalSecret` (`*-externalsecret.yaml`), materialized into native
  Secrets at runtime by the **External Secrets Operator (ESO)**, which authenticates to **OpenBao**
  (KV v2, path prefix `secret/data/k3s/`) via its ServiceAccount JWT (`auth/kubernetes`, ClusterSecretStore
  `openbao`). No secret ever lives in Git — values are provisioned by `ansible-services`
  (`openbao_k3s_secrets`). The only bootstrap secret created outside Git is ArgoCD's repo deploy key
  (`argocd-repo-creds`, created by ansible-k3s).

### Sync order (sync-waves)

```
-10 external-secrets   →   -9 external-snapshotter   →   -8 ceph-csi / nfs-csi / smb-csi
   →   -7 cert-manager   →   -6 external-dns   →   -5 observability   →   -4 kured
```

---

## Step 0 — Prerequisites

- **ansible-services** deployed (OpenBao unsealed, KV v2 `secret/` populated with the
  `k3s/...` secrets used by this layer, policies `eso-k3s-policy` + AppRole `ansible`).
- **ansible-k3s** playbook.yml run at least once (registers the K3s `auth/kubernetes` engine and the
  OpenBao role `eso-k3s`).
- `kubectl`/`kustomize` on your machine to validate renders.

---

## Step 1 — Central cluster settings: `components/cluster-settings/`

Edit [`components/cluster-settings/cluster-settings.yaml`](./components/cluster-settings/cluster-settings.yaml) to configure your Git repository, domain, and network subnets:

```yaml
data:
  repoURL: git@github.com:MrCaptainDartz/k3s-cluster.git   # ← YOUR Git repository
  targetRevision: main                                     # ← YOUR branch
  cephSubnet: 10.20.3.0/24                                 # ← Ceph network CIDR
  nodesSubnet: 10.20.4.0/24                                # ← K3s nodes subnet
  servicesSubnet: 10.20.4.0/24                             # ← Infra services VM subnet (OpenBao)
  podsSubnet: 10.42.0.0/16                                 # ← K3s pod CIDR
  domainName: captaindartz.org                             # ← Base cluster domain
```
*These parameters are automatically substituted into Ingress hosts, ClusterIssuers, ExternalDNS filters, and Zero-Trust NetworkPolicies across all add-ons.*

---

## Step 2 — Your secrets (OpenBao)

Secrets are stored in OpenBao KV v2 (`secret/`) and provisioned by **ansible-services**
(`openbao_k3s_secrets` in `ansible-services/inventory/group_vars/all.yml` — empty values are
auto-generated at deploy time). Adapt the paths/keys there to your environment; the expected
layout is:

```
k3s/ceph-csi-operator-system/csi-rbd-secret       (userID, userKey)
k3s/ceph-csi-operator-system/csi-cephfs-secret    (userID, userKey)
k3s/cert-manager/infomaniak-api-credentials       (api-token)
k3s/external-dns/infomaniak-api-token-cluster-domain (api-token)
k3s/monitoring/alertmanager-telegram              (bot-token, chat-id — NOT the full config:
                                                   the alertmanager.yaml skeleton lives in the
                                                   ESO template of alertmanager-externalsecret.yaml)
k3s/monitoring/grafana-admin-credentials          (admin-user, admin-password)
```

Each `gitops/infrastructure/<app>/*-externalsecret.yaml` maps those paths (via `remoteRef.key` /
`property`) onto the native Secret consumed by the app. To add/rotate a secret: update the value in
`ansible-services`, redeploy it, and ESO re-syncs within `refreshInterval` (1h) — or touch the
ExternalSecret to force a refresh.

---

## Step 3 — Adapt each add-on to your environment

Edit the following files under `infrastructure/<app>/` if you need custom configurations:

### 🌐 Routing & Certificates
- **`cert-manager/`**
  - `cluster-issuers.yaml`: Email and DNS zones automatically use `$(DOMAIN_NAME)` (adjust solver if using another DNS provider).
  - `infomaniak-externalsecret.yaml`: adjust OpenBao path if renamed.
- **`external-dns/`**
  - `values.yaml`: Domain filters and default targets automatically use `$(DOMAIN_NAME)`. Update provider image and txtOwnerId if needed.
  - `infomaniak-externalsecret.yaml`: adjust OpenBao path if renamed.

### 💾 Storage (CSI)
- **`ceph-csi/`**
  - `operator-config.yaml`: Set your Ceph `monitors` IPs.
  - `storageclasses.yaml`: Update `pool`, `fsName`, and secret names.
  - `ceph-secrets-externalsecret.yaml`: adjust OpenBao paths if needed.
  - Network policies automatically use `$(CEPH_SUBNET)`.
- **`nfs-csi/` & `smb-csi/`** *(Disabled by default)*
  - `storageclasses.yaml`: Set server IP, share path/source, and credentials. Enable in `kustomization.yaml`.

### 📊 Observability & System
- **`observability/`**
  - `kps-values.yaml`: Ingress hosts automatically use `grafana.$(DOMAIN_NAME)`. Admin credentials come from `grafana-admin-externalsecret.yaml` / OpenBao; Alertmanager config skeleton lives in `alertmanager-externalsecret.yaml`.
  - `loki-values.yaml`: Define a valid `storageClass` (e.g. `proxmox-rbd`), or Loki will stay Pending.
  - `loki-ingress.yaml`: Ingress host automatically uses `loki.$(DOMAIN_NAME)` with IP allowlist on `$(SERVICES_SUBNET)` and `$(NODES_SUBNET)`.
- **`kured/`**
  - `values.yaml`: Set up your node reboot window (`configuration.period` / `startTime`).

---

## Step 4 — Enable / disable an add-on

Edit [`bootstrap/apps/kustomization.yaml`](./bootstrap/apps/kustomization.yaml) and comment out the
app in `resources:`:
```yaml
resources:
  - ceph-csi.yaml
  # - nfs-csi.yaml      # disabled
  # - smb-csi.yaml      # disabled
  ...
```
The corresponding `Application` won't be created, so ArgoCD won't sync that infrastructure dir.
(Each Application already has `prune: true` + `selfHeal: true`, so disabling removes the resources.)

---

## Step 5 — Validate locally

```bash
# Renders the 9 Applications + cluster-settings (no Helm needed):
kubectl kustomize gitops/bootstrap/apps

# Render a single infra app (needs Helm for the helmCharts ones):
kubectl kustomize gitops/infrastructure/ceph-csi
kubectl kustomize gitops/infrastructure/observability   # needs helm + chart download
```
A `# Warning: 'vars' is deprecated…` line may appear — it is cosmetic and non-blocking (exit 0);
ArgoCD synchronizes normally.

---

## Notes & caveats

- **First-sync CRD timing**: apps whose manifests depend on CRDs installed by *another* app
  (e.g. `observability/rules.yaml` ServiceMonitors need the Prometheus Operator CRDs shipped by the
  kps helm chart) may be skipped on the very first apply and succeed on the next sync — ArgoCD
  `selfHeal` resolves this automatically.
- **Zero Trust NetworkPolicies**: Kube API egress is strictly restricted to `$(NODES_SUBNET)` across all add-ons.
- **Secrets are `ExternalSecret` CRs**, not native `Secret`s. ESO (wave -10) reconciles them into
  native Secrets from OpenBao. Do not convert them to plain `Secret`s — and never commit plaintext:
  secret values belong in OpenBao (`ansible-services`), not in this repo.
- **ESO auth chain**: `ansible-k3s` post-tasks bind the OpenBao role `eso-k3s` to SA
  `external-secrets` (ns `external-secrets`, audience `https://kubernetes.default.svc.cluster.local`).
  Renaming the ESO ServiceAccount or namespace breaks the TokenReview login.
