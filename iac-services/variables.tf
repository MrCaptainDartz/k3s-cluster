# ============================================================
# Provider / API Proxmox
# ============================================================

variable "proxmox_api_url" {
  type        = string
  description = "URL of the Proxmox API (e.g., https://10.20.0.11:8006/api2/json)"
}

variable "proxmox_api_token" {
  type        = string
  description = "Proxmox API token (e.g., root@pam!opentofu=uuid)"
  sensitive   = true
}

variable "proxmox_ssh_username" {
  type        = string
  description = "SSH username used by the provider to connect to Proxmox nodes"
  default     = "root"
}

variable "proxmox_insecure" {
  type        = bool
  description = "Disable TLS certificate verification for the Proxmox API"
  default     = true
}

# ============================================================
# Image Cloud-Init
# ============================================================

variable "ubuntu_cloud_image_url" {
  type        = string
  description = "URL of the Ubuntu Cloud-Init image to download on the Proxmox node"
  default     = "https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img"
}

variable "ubuntu_cloud_image_filename" {
  type        = string
  description = "Filename used to store the Cloud-Init image on Proxmox"
  default     = "ubuntu-26.04-resolute-server-cloudimg-amd64.img"
}

variable "image_datastore_id" {
  type        = string
  description = "Proxmox datastore where the Cloud-Init ISO image is stored (must be a directory datastore)"
  default     = "local"
}

variable "enable_cloudinit_snippet" {
  type        = bool
  description = "Whether to upload and use a custom Cloud-Init snippet to install and start qemu-guest-agent on first boot"
  default     = true
}

variable "snippet_datastore_id" {
  type        = string
  description = "Proxmox datastore where Cloud-Init snippets are stored. Defaults to image_datastore_id."
  default     = null
}

# ============================================================
# VM Configuration
# ============================================================

variable "vm_name" {
  type        = string
  description = "Name of the dedicated infrastructure services VM"
  default     = "infra-services"
}

variable "node_name" {
  type        = string
  description = "Target Proxmox node where the VM is hosted"
  default     = "pve-node-1"
}

variable "cluster_nodes" {
  type        = list(string)
  description = "List of all Proxmox nodes in the cluster (snippets are uploaded to all nodes for seamless HA migration)"
  default     = ["pve-node-1", "pve-node-2", "pve-node-3"]
}

variable "vm_id" {
  type        = number
  description = "Optional custom VM ID in Proxmox (auto-assigned if null)"
  default     = null
}

variable "vm_description" {
  type        = string
  description = "Description for the VM in Proxmox"
  default     = "Managed by OpenTofu - Dedicated Infra Services (Forgejo, Infisical)"
}

variable "vm_tags" {
  type        = list(string)
  description = "Tags applied to the VM in Proxmox"
  default     = ["services", "gitops", "infisical", "forgejo", "opentofu"]
}

variable "pool_id" {
  type        = string
  description = "Optional Proxmox resource pool ID to assign the VM to (e.g. 'Backup-Daily')"
  default     = "Backup-Daily"
}

variable "vm_cpu_cores" {
  type        = number
  description = "Number of vCPU cores allocated to the VM"
  default     = 4
}

variable "vm_cpu_type" {
  type        = string
  description = "CPU emulation type"
  default     = "x86-64-v2-AES"
}

variable "vm_memory_mb" {
  type        = number
  description = "Memory (RAM) in MiB allocated to the VM"
  default     = 8192
}

variable "vm_disk_size_gb" {
  type        = number
  description = "Disk size in GiB"
  default     = 80
}

variable "vm_disk_datastore_id" {
  type        = string
  description = "Datastore for the VM disk (Ceph storage pool for HA reliability)"
  default     = "pool1_ssd"
}

variable "vm_disk_interface" {
  type        = string
  description = "Disk interface type"
  default     = "scsi0"
}

variable "vm_machine_type" {
  type        = string
  description = "QEMU machine type"
  default     = "q35"
}

variable "vm_bios" {
  type        = string
  description = "BIOS type: 'ovmf' (UEFI) or 'seabios'"
  default     = "ovmf"
}

variable "vm_vga_type" {
  type        = string
  description = "VGA display type"
  default     = "qxl"
}

variable "vm_keyboard_layout" {
  type        = string
  description = "Keyboard layout"
  default     = "fr"
}

variable "vm_disk_iothread" {
  type        = bool
  description = "Enable dedicated IOThread for the disk (improves I/O performance on SSD/Ceph)"
  default     = true
}

variable "vm_scsi_hardware" {
  type        = string
  description = "SCSI controller hardware type (e.g. 'virtio-scsi-single', 'virtio-scsi-pci')"
  default     = "virtio-scsi-single"
}

variable "vm_boot_order" {
  type        = list(string)
  description = "Boot device order list"
  default     = ["scsi0"]
}

variable "vm_start_on_boot" {
  type        = bool
  description = "Start the VM automatically on Proxmox node boot"
  default     = true
}

variable "vm_startup_order" {
  type        = number
  description = "Startup order of the VM on Proxmox node boot (1 = first)"
  default     = 1
}

variable "vm_startup_up_delay" {
  type        = number
  description = "Delay in seconds after starting this VM before starting the next VM (e.g. 60)"
  default     = 60
}

# ============================================================
# Network & Access
# ============================================================

variable "network_bridge" {
  type        = string
  description = "Proxmox network bridge interface"
  default     = "vmbr0"
}

variable "network_vlan_id" {
  type        = number
  description = "VLAN ID for the main network interface"
  default     = 2004
}

variable "ip_address" {
  type        = string
  description = "Static IPv4 address with CIDR netmask"
  default     = "10.20.4.253/24"
}

variable "gateway" {
  type        = string
  description = "Default IPv4 gateway"
  default     = "10.20.4.254"
}

variable "dns_servers" {
  type        = list(string)
  description = "DNS servers configured via Cloud-Init"
  default     = ["10.20.4.254"]
}

variable "dns_domain" {
  type        = string
  description = "DNS domain configured via Cloud-Init"
  default     = "."
}

variable "vm_user" {
  type        = string
  description = "Admin SSH user injected via Cloud-Init"
  default     = "ubuntu"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key injected via Cloud-Init"
  sensitive   = true
}

# ============================================================
# Proxmox High Availability (HA)
# ============================================================

variable "enable_ha" {
  type        = bool
  description = "Register the infra-services VM in Proxmox HA manager"
  default     = true
}

variable "ha_group" {
  type        = string
  description = "Optional Proxmox HA group to assign the VM to (null for all nodes / cluster default)"
  default     = null
}

variable "ha_state" {
  type        = string
  description = "Desired HA state: 'started', 'stopped', 'ignored'"
  default     = "started"
}

variable "ha_max_restart" {
  type        = number
  description = "Maximum number of restart attempts by HA manager before relocation"
  default     = 1
}

variable "ha_max_relocate" {
  type        = number
  description = "Maximum number of relocation attempts by HA manager"
  default     = 1
}
