# 🚀 Hyperconverged Cluster Homelab: IaC & K3s & GitOps

This repository provides a complete solution for deploying a **Hyperconverged Infrastructure (HCI)** at home on a Proxmox VE cluster.

From initial VM provisioning to a highly available K3s cluster with persistent storage, this project automates the entire stack using modern Infrastructure-as-Code (IaC) principles with **OpenTofu**, **Ansible**, and **ArgoCD**.

---

## 🏗️ Project Vision

The mission of this project is to bridge the gap between "experimental homelabbing" and "professional cloud-native infrastructure". By treating your domestic hardware like a private cloud, you achieve:

1.  **Seamless Infrastructure Provisioning**: Fully automated Ubuntu VM deployment on Proxmox.
2.  **Highly Available Kubernetes**: A resilient K3s cluster.
3.  **Hyperconverged Storage**: Integrated **Ceph** storage providing cloud-native persistent volumes.
4.  **GitOps Workflows**: Automatic synchronization of applications and infrastructure state via ArgoCD.

---

## 🛠️ Architecture & Workflow

The project is split into three main logical layers:

### Layer 1: Infrastructure (IaC)
Located in [`iac/`](./iac/), this part uses **OpenTofu** to talk to the Proxmox API to provision VMs.

### Layer 2: Bootstrap (Ansible)
Located in [`ansible-k3s/`](./ansible-k3s/), this part uses **Ansible** to bootstrap K3s, MetalLB, SOPS, and ArgoCD on the VMs.

### Layer 3: GitOps (ArgoCD)
Located in [`gitops/`](./gitops/), this layer manages all Kubernetes infrastructure (Cert-Manager, ExternalDNS, Ceph CSI, Observability) via GitOps.
The Git source (repo URL + branch) used by every ArgoCD Application is centralized in `gitops/components/cluster-settings/cluster-settings.yaml` and injected into the manifests by Kustomize — edit that one file when forking the repo.

---

## 📋 Global Prerequisites

### 🖥️ Infrastructure (Proxmox VE)
- **Functional Cluster**: A Proxmox cluster (v7+ or v8+).
- **Storage**: Ceph cluster running on Proxmox nodes (or external).
- **Network**: All nodes must be on the same L2 network.

### 💻 Control Machine
- **OpenTofu / Ansible / SOPS / kubectl / age** installed.

---

## 🚀 Quick Start

1. **Deploy VMs (OpenTofu)**:
   ```bash
   cd iac/
   cp terraform.tfvars.example terraform.tfvars # Edit with your details
   tofu init && tofu apply
   ```

2. **Configure GitOps & Secrets**:
   - Generate an Age key: `age-keygen -o age.key`
   - Encrypt your secrets in the `gitops/` directory using `sops` (the `*.sops.yaml` files).
   - Edit `gitops/components/cluster-settings/cluster-settings.yaml` — the single place for the Git source ArgoCD syncs (repo URL + branch), injected into the Applications by Kustomize.
   - Edit `gitops/infrastructure/cert-manager/cluster-issuers.yaml` to configure your DNS provider, zone, and Let's Encrypt email.
   - Edit `gitops/infrastructure/external-dns/values.yaml` to match your DNS provider and domain.
   - Edit your preferred storage classes in `gitops/infrastructure/{ceph-csi,nfs-csi,smb-csi}/` if needed.
   - Update `ansible-k3s/inventory/group_vars/all.yml` with your SSH deploy key, Age private key, ArgoCD domain, and repo URL.

3. **Bootstrap K3s & ArgoCD**:
   ```bash
   cd ../ansible-k3s/
   ansible-galaxy install -r requirements.yml
   cp inventory/hosts.yml.example inventory/hosts.yml # Insert IPs from IaC
   cp inventory/group_vars/all.yml.example inventory/group_vars/all.yml # Edit configs!
   ansible-playbook -i inventory/hosts.yml site.yml
   ```

4. **ArgoCD takes over!**
   ArgoCD will automatically deploy everything inside the `gitops/` directory.

---

## 🤝 Acknowledgments
Based on [**ansible-role-k3s**](https://github.com/PyratLabs/ansible-role-k3s) by **Xan Manning**.
