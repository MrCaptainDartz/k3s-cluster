# GitOps layer (ArgoCD)

This directory defines the **desired state** of the cluster's add-on stack. ArgoCD continuously synchronizes `gitops/` after Ansible bootstraps K3s.

## Quick Start
**0. Prerequisites**: 
- `age-keygen -o age.key` (put private key in `ansible-k3s/inventory/group_vars/all.yml` and public in `.sops.yaml`)
- Install `sops`, `kubectl`, and `kustomize`.

**1. Point ArgoCD to your fork**:
Edit `components/cluster-settings/cluster-settings.yaml`:
```yaml
data:
  repoURL: git@github.com:MrCaptainDartz/k3s-cluster.git # Your repo
  targetRevision: main                                   # Your branch
```

**2. Configure SOPS**:
Update `.sops.yaml` with your public Age key. Re-encrypt secrets if needed: `find gitops -name '*.sops.yaml' -exec sops updatekeys {} \;`. Edit secrets via `sops edit <file>`.

**3. Adapt Add-ons**:
- **cert-manager**: Update `cluster-issuers.yaml` (email, dnsZones). Edit `dns-credentials-*.sops.yaml` with your token.
- **external-dns**: Update `values.yaml` (domainFilters). Edit `dns-credentials.sops.yaml`.
- **ceph-csi**: Update `operator-config.yaml` (monitors), `storageclasses.yaml`, and `ceph-secrets.sops.yaml`.
- **observability**: Edit `kps-values.yaml` (adminPassword) and `loki-values.yaml` (storageClass).

**4. Enable/Disable Add-ons**:
Comment/uncomment resources in `bootstrap/apps/kustomization.yaml` to toggle apps.

**5. Validate**:
```bash
kubectl kustomize gitops/bootstrap/apps
kubectl kustomize gitops/infrastructure/<app>
```

**Notes**:
- **Sync order**: sops-providers → external-snapshotter → CSI → cert-manager → external-dns → observability → kured
- **Secrets**: Must be `SopsSecret`. Never commit plaintext secrets.
- **NPs**: Tighten `0.0.0.0/0` egress rules to your node CIDR for zero-trust.
