# GitOps layer (ArgoCD)

This directory is the **desired state** of the cluster's add-on stack. Once Ansible has bootstrapped
K3s + SOPS Operator + ArgoCD (see [`../ansible-k3s/`](../ansible-k3s/)), ArgoCD continuously
synchronizes everything under `gitops/`.

This README is a **quick start for adapting the repo to your own environment** (different domain,
DNS provider, Ceph cluster, NAS shares, observability, etc.).

---

## How it is wired

```
gitops/
├── .sops.yaml                                  # SOPS config: age recipient + which fields to encrypt
├── components/cluster-settings/                 # Shared Kustomize component (repo URL + branch)
├── bootstrap/
│   └── apps/                                    # App-of-apps: one Application per add-on (rendered by Kustomize)
└── infrastructure/                              # The actual manifests of each add-on
    ├── ceph-csi/  cert-manager/  external-dns/  external-snapshotter/
    ├── kured/  nfs-csi/  observability/  smb-csi/  sops-providers/
```

- The Ansible template `11-root-app.yml.j2` creates the **root `Application`** that points ArgoCD at
  `gitops/bootstrap/apps/`.
- That path has a `kustomization.yaml` → ArgoCD renders it via **Kustomize** and creates one
  `Application` per add-on (app-of-apps pattern).
- Each `Application` points to its own `gitops/infrastructure/<app>/` directory, also rendered by
  Kustomize (helm charts + raw manifests).
- **Secrets** live as `kind: SopsSecret` (`*.sops.yaml`), decrypted at runtime by the
  **SOPS Operator** (bootstrapped by Ansible) using your Age key. Never put plaintext secrets here.

### Sync order (sync-waves)

```
-10 sops-providers   →   -9 external-snapshotter   →   -8 ceph-csi / nfs-csi / smb-csi
   →   -7 cert-manager   →   -6 external-dns   →   -5 observability   →   -4 kured
```

---

## Step 0 — Prerequisites

- Your **Age keypair** generated (`age-keygen -o age.key`). The **private** key goes into
  `ansible-k3s/inventory/group_vars/all.yml` (gitignored); the **public** key goes into
  [`./.sops.yaml`](./.sops.yaml) (`age:` recipient).
- `sops` and `kubectl`/`kustomize` on your machine to edit secrets and validate renders.

---

## Step 1 — The one central file: `components/cluster-settings/`

Edit [`components/cluster-settings/cluster-settings.yaml`](./components/cluster-settings/cluster-settings.yaml) to point ArgoCD to your fork:

```yaml
data:
  repoURL: git@github.com:MrCaptainDartz/k3s-cluster.git   # ← YOUR repo
  targetRevision: main                                     # ← YOUR branch
```
*Note: All other settings (domain, storage, etc.) are local to each app's directory. We do not centralize them to keep helm charts configuration intact.*

---

## Step 2 — Your Age key & SOPS config

Update your public Age key in [`./.sops.yaml`](./.sops.yaml) (must match the private key in Ansible):
```yaml
creation_rules:
  - path_regex: \.sops\.yaml$
    encrypted_regex: '^(data|stringData)$'
    age: "age1..."        # ← YOUR age PUBLIC key
```

- **Re-encrypt all secrets** (if key changed): `find gitops -name '*.sops.yaml' -exec sops updatekeys {} \;`
- **Edit an existing secret**: `sops edit gitops/infrastructure/<app>/<file>.sops.yaml`

---

## Step 3 — Adapt each add-on to your environment

Edit the following files under `infrastructure/<app>/` to match your environment:

### 🌐 Routing & Certificates
- **`cert-manager/`**
  - `cluster-issuers.yaml`: Update `email`, `dnsZones`, and uncomment your provider's solver.
  - `dns-credentials-*.sops.yaml`: Add your DNS API token via `sops edit`.
- **`external-dns/`**
  - `values.yaml`: Update `provider` image, `domainFilters`, and `txtOwnerId`.
  - `dns-credentials.sops.yaml`: Set your API token.

### 💾 Storage (CSI)
- **`ceph-csi/`**
  - `operator-config.yaml`: Set your Ceph `monitors` IPs.
  - `storageclasses.yaml`: Update `pool`, `fsName`, and secret names.
  - `ceph-secrets.sops.yaml`: Set `userID` and `userKey`.
  - `network-policies.yaml`: Restrict `allow-egress-ceph` to your Ceph network CIDR.
- **`nfs-csi/` & `smb-csi/`** *(Disabled by default)*
  - `storageclasses.yaml`: Set server IP, share path/source, and credentials. Enable in `kustomization.yaml`.

### 📊 Observability & System
- **`observability/`**
  - `kps-values.yaml`: Change `grafana.adminPassword` (default `admin`), `grafana.ingress.hosts`. Add `storageSpec` if you want persistent Prometheus metrics.
  - `loki-values.yaml`: Define a valid `storageClass` (e.g. `proxmox-rbd`), or Loki will stay Pending.
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
- **Broad egress NPs**: cert-manager/external-dns/ceph `allow-egress-kubeapi` use `0.0.0.0/0`. Tighten
  to your node CIDR for a stricter zero-trust posture.
- **Secrets are `SopsSecret` CRs**, not native `Secret`s. They are reconciled into native Secrets by
  the SOPS Operator (Ansible deploys it). Do not convert them to plain `Secret`s.
- **Never commit plaintext secrets** — always go through `sops edit`. The `.sops.yaml`
  `encrypted_regex: ^(data|stringData)$` ensures only the payload is encrypted; metadata stays readable.
