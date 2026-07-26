# HA K3s Cluster Bootstrap (Ansible)

Bootstraps a 3-node HA K3s cluster and prepares the GitOps controller (ArgoCD).

## Features
Installs: **K3s** (HA + etcd), **kube-vip**, **MetalLB**, **Traefik**, **SOPS Operator** (decrypts secrets), and **ArgoCD**.

## GitOps Handoff
ArgoCD is installed and pointed to `gitops/bootstrap/apps/` via `11-root-app.yml.j2`, triggering the "app-of-apps" deployment automatically.

## Quick Start
1. `ansible-galaxy install -r requirements.yml`
2. `cp inventory/hosts.yml.example inventory/hosts.yml`
3. `cp inventory/group_vars/all.yml.example inventory/group_vars/all.yml`
4. **Edit `all.yml`**: Set network details, Age private key, ArgoCD domain, and SSH deploy key.
5. `ansible-playbook -i inventory/hosts.yml site.yml`

*ArgoCD takes over automatically once finished!*