output "vm_name" {
  description = "Name of the deployed VM"
  value       = proxmox_virtual_environment_vm.infra_services.name
}

output "vm_id" {
  description = "VM ID in Proxmox"
  value       = proxmox_virtual_environment_vm.infra_services.vm_id
}

output "node_name" {
  description = "Proxmox node hosting the VM"
  value       = proxmox_virtual_environment_vm.infra_services.node_name
}

output "ipv4_address" {
  description = "Configured static IPv4 address"
  value       = var.ip_address
}

output "ssh_command" {
  description = "SSH connection command for admin user"
  value       = "ssh ${var.vm_user}@${split("/", var.ip_address)[0]}"
}
