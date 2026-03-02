output "nic_id" {
  value = azurerm_network_interface.my_nic.id
}

output "fqdn" {
  value = azurerm_public_ip.my_public_ip.fqdn
}