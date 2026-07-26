# Proxmox Homelab Infrastructure (IaC)

Automates deployment of Ubuntu VMs on Proxmox VE using **OpenTofu**.

## 🚀 Features
- **Cloud-Init Integration**: Auto-injects SSH keys and installs QEMU Guest Agent.
- **Image Management**: Auto-downloads Ubuntu Cloud Images.
- **Flexible Specs**: Configurable vCPU, RAM, Disk, and Networks.

## 📋 Prerequisites
- Proxmox VE Cluster with API Token and SSH enabled.
- OpenTofu (or Terraform >= 1.11.0).

## 🛠️ Quick Start

**1. Configure Variables**:
```bash
cp terraform.tfvars.example terraform.tfvars # Edit with your details
```

**2. Define VMs in `terraform.tfvars`**:
```hcl
vm_config = {
  "vm-name" = {
    node_name          = "pve-node-1"
    network_interfaces = [
      { bridge = "vmbr0", address = "10.0.0.10/24", gateway = "10.0.0.1" }
    ]
  }
}
```

**3. Deploy**:
```bash
tofu init
tofu apply
```

## 🔍 Notes
- The QEMU Guest Agent is installed on first boot by Cloud-Init. Wait a minute if Proxmox reports it as missing.
- Default credentials: user `ubuntu` with your injected SSH key.
