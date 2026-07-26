# HA K3s Cluster Bootstrap (Ansible)

This directory contains the Ansible playbook responsible for bootstrapping a 3-node HA K3s cluster. It prepares the baseline infrastructure so that ArgoCD (the GitOps controller) can take over.

## What it does

Out of the box, this playbook installs and configures:
- **3 Control Plane nodes** with embedded etcd for HA.
- **[kube-vip](https://kube-vip.io/)** — Virtual IP (VIP) for the Kubernetes API server.
- **[MetalLB](https://metallb.universe.tf/)** — L2 LoadBalancer for incoming traffic.
- **[Traefik](https://traefik.io/)** — Ingress controller.
- **SOPS Operator** (peak-scale) — To decrypt GitOps secrets securely using an Age key.
- **ArgoCD** — The GitOps engine that automatically synchronizes the `gitops/` directory.

## Project Structure

```
ansible-k3s/
├── ansible.cfg                          # Local Ansible settings
├── requirements.yml                     # Dependencies (PyratLabs k3s role)
├── site.yml                             # The main playbook
├── inventory/
│   ├── hosts.yml.example                # Blank inventory (add your IPs here)
│   └── group_vars/
│       └── all.yml.example              # Central configuration variables
└── templates/
    ├── 01-kube-vip-rbac.yml.j2
    ├── 02-kube-vip-daemonset.yml.j2
    ├── 04-metallb-config.yml.j2
    ├── 05-network-policies.yml.j2
    ├── 06-traefik-config.yml.j2
    ├── 07-pod-security.yml.j2
    ├── 08-sops-operator.yml.j2          # Bootstraps SOPS for secret decryption
    ├── 09-argocd.yml.j2                 # Bootstraps ArgoCD
    ├── 10-coredns-pdb.yml.j2
    └── 11-root-app.yml.j2          # Seeds the ArgoCD "app-of-apps" root Application
```

## Bootstrap → GitOps handoff

`09-argocd.yml.j2` installs ArgoCD, and `11-root-app.yml.j2` drops the root `Application` that points ArgoCD at `gitops/bootstrap/apps/`. From there ArgoCD recursively deploys every app defined in `gitops/` (app-of-apps pattern). The Git source (repo URL + branch) for the ArgoCD Applications is injected by Kustomize from `gitops/components/cluster-settings/cluster-settings.yaml`.

## How to use

1. Install requirements:
   ```bash
   ansible-galaxy install -r requirements.yml
   ```
2. Prepare your inventory:
   ```bash
   cp inventory/hosts.yml.example inventory/hosts.yml
   cp inventory/group_vars/all.yml.example inventory/group_vars/all.yml
   ```
3. **Important:** Edit `inventory/group_vars/all.yml` with your network details, Age private key, ArgoCD domain, and SSH deploy key.

4. Run the playbook:
   ```bash
   ansible-playbook -i inventory/hosts.yml site.yml
   ```

*Once the playbook finishes, ArgoCD will automatically deploy everything else from the `gitops/` folder!*