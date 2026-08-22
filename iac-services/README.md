# Infrastructure as Code — `infra-services` VM (OpenTofu)

Provisions the dedicated standalone **`infra-services`** Virtual Machine on Proxmox VE to host core infrastructure services (**Forgejo**, **Infisical**, **Traefik v3**).

---

## ⚙️ Configuration

Copy and customize the variable definition file:
```bash
cp terraform.tfvars.example terraform.tfvars
```

Key variables to review in `terraform.tfvars`:
- `proxmox_api_endpoint`, `proxmox_api_token`: Proxmox VE API credentials.
- `target_node`: Target Proxmox node (e.g. `srv-tlm-hc1`).
- `pool_id`: Proxmox resource pool (default: `Backup-Daily`).
- `vm_ip`, `vm_gateway`, `vlan_tag`: Static IPv4 network configuration.
- `ssh_public_keys`: SSH authorized keys for admin access (`ubuntu` user).

---

## 🚀 Quickstart

```bash
# 1. Initialize OpenTofu and download providers
tofu init

# 2. Review execution plan
tofu plan

# 3. Provision the VM and register in Proxmox HA
tofu apply
```

Once the VM is ready, proceed to [`../ansible-services/`](../ansible-services/) to configure the OS and deploy the services.
