# 🚀 Hyperconverged Cluster Homelab: IaC & K3s & GitOps

Complete solution for deploying a **Hyperconverged Infrastructure (HCI)** at home on Proxmox VE. Automates VM provisioning (OpenTofu), K3s HA clustering (Ansible), and GitOps (ArgoCD).

## 🛠️ Architecture
- **Layer 1: IaC (`iac/`)**: OpenTofu provisions Ubuntu VMs on Proxmox.
- **Layer 2: Bootstrap (`ansible-k3s/`)**: Ansible configures K3s, MetalLB, SOPS, and ArgoCD.
- **Layer 3: GitOps (`gitops/`)**: ArgoCD synchronizes add-ons (Cert-Manager, Ceph CSI, Observability).

## 📋 Prerequisites
- Proxmox VE cluster (v7+) with Ceph storage.
- Control Machine: OpenTofu, Ansible, SOPS, kubectl, age.

## 🚀 Quick Start
**1. Deploy VMs (OpenTofu)**:
```bash
cd iac/
cp terraform.tfvars.example terraform.tfvars # Edit it
tofu init && tofu apply
```

**2. Configure GitOps & Secrets**:
- Generate key: `age-keygen -o age.key`
- Edit `gitops/components/cluster-settings/cluster-settings.yaml` to point to your fork.
- Update `cert-manager/cluster-issuers.yaml` and `external-dns/values.yaml` for your domain.
- Edit `ansible-k3s/inventory/group_vars/all.yml` with your IPs and secrets.

**3. Bootstrap K3s**:
```bash
cd ../ansible-k3s/
ansible-galaxy install -r requirements.yml
cp inventory/hosts.yml.example inventory/hosts.yml
cp inventory/group_vars/all.yml.example inventory/group_vars/all.yml
ansible-playbook -i inventory/hosts.yml site.yml
```
*ArgoCD takes over automatically once finished!*

## 🤝 Acknowledgments
Based on [**ansible-role-k3s**](https://github.com/PyratLabs/ansible-role-k3s) by **Xan Manning**.
