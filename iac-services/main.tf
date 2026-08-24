# Download Ubuntu Cloud-Init image on target Proxmox node
resource "proxmox_download_file" "ubuntu_cloud_image" {
  content_type        = "iso"
  datastore_id        = var.image_datastore_id
  node_name           = var.node_name
  url                 = var.ubuntu_cloud_image_url
  file_name           = var.ubuntu_cloud_image_filename
  overwrite           = false
  overwrite_unmanaged = true
}

# Cloud-Init snippet uploaded to all cluster nodes for HA migration support
resource "proxmox_virtual_environment_file" "vendor_config" {
  for_each     = var.enable_cloudinit_snippet ? toset(var.cluster_nodes) : []
  content_type = "snippets"
  datastore_id = coalesce(var.snippet_datastore_id, var.image_datastore_id)
  node_name    = each.key

  source_raw {
    data      = <<EOF
#cloud-config
package_update: true
package_upgrade: true
package_reboot_if_required: true
packages:
  - qemu-guest-agent

runcmd:
  - systemctl daemon-reload
  - systemctl enable --now qemu-guest-agent
  - systemctl restart qemu-guest-agent
EOF
    file_name = "vendor-cloudinit-services.yaml"
  }
}

# Dedicated Infrastructure Services VM (Forgejo + OpenBao)
resource "proxmox_virtual_environment_vm" "infra_services" {
  name        = var.vm_name
  vm_id       = var.vm_id
  node_name   = var.node_name
  description = var.vm_description
  tags        = var.vm_tags
  pool_id     = var.pool_id

  on_boot = var.vm_start_on_boot

  startup {
    order    = var.vm_startup_order
    up_delay = var.vm_startup_up_delay
  }

  machine       = var.vm_machine_type
  bios          = var.vm_bios
  scsi_hardware = var.vm_scsi_hardware
  boot_order    = var.vm_boot_order

  # EFI disk required when UEFI (ovmf) is enabled
  dynamic "efi_disk" {
    for_each = var.vm_bios == "ovmf" ? [1] : []
    content {
      datastore_id      = var.vm_disk_datastore_id
      file_format       = "raw"
      type              = "4m"
      pre_enrolled_keys = true
    }
  }

  agent {
    enabled = true
    trim    = true
    timeout = "15m"
  }

  cpu {
    cores = var.vm_cpu_cores
    type  = var.vm_cpu_type
  }

  memory {
    dedicated = var.vm_memory_mb
  }

  disk {
    datastore_id = var.vm_disk_datastore_id
    file_id      = proxmox_download_file.ubuntu_cloud_image.id
    interface    = var.vm_disk_interface
    size         = var.vm_disk_size_gb
    discard      = "on"
    ssd          = true
    iothread     = var.vm_disk_iothread
  }

  network_device {
    bridge  = var.network_bridge
    vlan_id = var.network_vlan_id
    model   = "virtio"
  }

  initialization {
    # Storage where Cloud-Init drive is generated (Ceph pool1_ssd for HA replication across all nodes)
    datastore_id = var.vm_disk_datastore_id

    # Inject cloud-init snippet (available on all cluster nodes)
    vendor_data_file_id = var.enable_cloudinit_snippet ? proxmox_virtual_environment_file.vendor_config[var.node_name].id : null

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.dns_domain
    }

    user_account {
      username = var.vm_user
      keys     = [var.ssh_public_key]
    }
  }

  vga {
    type = var.vm_vga_type
  }

  rng {
    source = "/dev/urandom"
  }

  operating_system {
    type = "l26" # Linux 2.6 / 5.x / 6.x kernel
  }

  # Prevent OpenTofu from destroying or moving the VM when HA migrates it to another node
  lifecycle {
    ignore_changes = [
      node_name,
    ]
  }
}

# Proxmox HA Manager Registration for infra-services VM
resource "proxmox_haresource" "infra_services" {
  count        = var.enable_ha ? 1 : 0
  depends_on   = [proxmox_virtual_environment_vm.infra_services]
  resource_id  = "vm:${proxmox_virtual_environment_vm.infra_services.vm_id}"
  state        = var.ha_state
  group        = var.ha_group
  comment      = "HA for infra-services VM (Forgejo + OpenBao)"
  max_restart  = var.ha_max_restart
  max_relocate = var.ha_max_relocate
}
