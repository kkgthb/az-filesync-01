resource "azurerm_public_ip" "my_public_ip" {
  name                = "${var.workload_nickname}WinPublicIp"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"
  domain_name_label   = "${var.workload_nickname}mywinvmfqdn"
}

resource "github_actions_secret" "gh_scrt_vm_fqdn" {
  repository      = var.current_gh_repo
  secret_name     = "THE_WINDOWS_VM_FQDN"
  plaintext_value = azurerm_public_ip.my_public_ip.fqdn
  depends_on      = [azurerm_public_ip.my_public_ip]
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "my_nsg" {
  name                = "${var.workload_nickname}WinNsg"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name

  security_rule {
    name                       = "WinRM"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5986"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "RDP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_virtual_network" "my_vnet" {
  name                = "${var.workload_nickname}WinVnet"
  address_space       = ["10.0.0.0/16"]
  resource_group_name = var.resource_group.name
  location            = var.resource_group.location
}

resource "azurerm_subnet" "my_subnet" {
  name                 = "${var.workload_nickname}WinSubnet"
  resource_group_name  = var.resource_group.name
  virtual_network_name = azurerm_virtual_network.my_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_interface" "my_nic" {
  name                = "${var.workload_nickname}WinNic"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name

  ip_configuration {
    name                          = "${var.workload_nickname}Win_nic_configuration"
    subnet_id                     = azurerm_subnet.my_subnet.id
    public_ip_address_id          = azurerm_public_ip.my_public_ip.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "example" {
  network_interface_id      = azurerm_network_interface.my_nic.id
  network_security_group_id = azurerm_network_security_group.my_nsg.id
}

