# 🚀 Hyperconverged Cluster Homelab: IaC & K3s

This repository provides a complete solution for deploying a **Hyperconverged Infrastructure (HCI)** at home on a Proxmox VE cluster.

From initial VM provisioning to a production-ready, highly available K3s cluster with persistent storage, this project automates the entire stack using modern Infrastructure-as-Code (IaC) principles with **OpenTofu** and **Ansible**.

---

## 🏗️ Project Vision

The mission of this project is to bridge the gap between "experimental homelabbing" and "professional cloud-native infrastructure". By treating your domestic hardware like a private cloud, you achieve:

1.  **Seamless Infrastructure Provisioning**: Fully automated Ubuntu 24.04 VM deployment on Proxmox, ensuring consistent builds every time.
2.  **Highly Available Kubernetes**: A resilient K3s cluster (control plane + etcd) designed for maximum uptime and reliability.
3.  **Hyperconverged Storage**: Integrated **Ceph** storage (ideally co-located on Proxmox nodes) providing cloud-native persistent volumes (RBD & CephFS).
4.  **Advanced Networking**: Automated Virtual IP (VIP) management for the API server and dynamic LoadBalancer services via MetalLB.

---

## 🛠️ Architecture & Workflow

The project is split into two main logical layers, each with its own dedicated documentation:

### Layer 1: Infrastructure (IaC)

Located in [`iac/`](./iac/), this part uses **OpenTofu** to talk to the Proxmox API.

- **Goal**: Provisioning the Virtual Machines.
- **Key Features**: Cloud-init injection, automated image management, and flexible hardware configuration.
- [Read more in the IaC README](./iac/README.md)

### Layer 2: Configuration (Ansible)

Located in [`ansible-k3s/`](./ansible-k3s/), this part uses **Ansible** to configure the provisioned VMs.

- **Goal**: Setting up the K3s cluster and its ecosystem.
- **Key Features**: HA Control Plane, Kube-VIP, MetalLB, and Ceph CSI storage classes.
- [Read more in the Ansible K3s README](./ansible-k3s/README.md)

---

## 📋 Global Prerequisites

Before you begin, ensure your environment meets the following requirements:

### 🖥️ Infrastructure (Proxmox VE)

- **Functional Cluster**: A Proxmox cluster (v7+ or v8+).
- **API Access**: A Proxmox API token with permissions for VM management.
- **Network**: All your nodes must be on the same L2 network.
- **Storage**:
  - Valid storage for VM disks (LVM-Thin, ZFS, or Ceph).
  - **Ceph**: Ideally, a Ceph cluster running directly on your Proxmox nodes to achieve a **Hyperconverged Infrastructure**. The project also supports external Ceph clusters.

### 💻 Control Machine (Your PC/Laptop)

- **Terraform / OpenTofu**: For provisioning the infrastructure.
- **Ansible**: For automating the system configuration.
- **Connectivity**: SSH access to your Proxmox nodes.

---

## 📂 Project Structure

```text
.
├── iac/                # Infrastructure-as-Code: VM provisioning on Proxmox
├── ansible-k3s/        # Configuration Management: K3s & storage orchestration
└── README.md           # You are here (Global overview)
```

---

## 🚀 Quick Start

1.  **Deploy VMs**:

    ```bash
    cd iac/
    cp terraform.tfvars.example terraform.tfvars # Edit with your details
    tofu init && tofu apply
    ```

2.  **Deploy K3s**:
    ```bash
    cd ../ansible-k3s/
    ansible-galaxy install -r requirements.yml
    cp inventory/hosts.yml.example inventory/hosts.yml # Use IPs from IaC
    cp inventory/group_vars/all.yml.example inventory/group_vars/all.yml # Edit configs
    ansible-playbook -i inventory/hosts.yml site.yml
    ```

---

## 🔍 Why this project?

Setting up a robust Kubernetes cluster in a homelab often involves repetitive manual steps (creating VMs, installing Docker/K3s, configuring networking). This project treats your homelab like a **Production Environment**, ensuring that your entire infrastructure is:

- **Reproducible**: Rebuilding your cluster takes minutes, not hours.
- **Version Controlled**: Any changes to your infra or K8s config are tracked in Git.
- **Highly Available**: Designed to survive the failure of any single node.

---

## 🤝 Acknowledgments

A special thank you to the creators of [**ansible-role-k3s**](https://github.com/PyratLabs/ansible-role-k3s) by **Xan Manning**, which serves as the core foundation for the K3s deployment in this project.

---

> [!TIP]
> Always check the detailed READMEs in the sub-directories for specific configuration variables and advanced options.
