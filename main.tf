terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.46.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "adlterraformgroup" {
  name     = "adlResourceGroupVM"
  location = "eastus"

  tags = {
    "Environment" = "MySQL"
  }
}

resource "azurerm_virtual_network" "adlterraformnetwork" {
  name                = "adlVnet"
  address_space       = ["10.0.0.0/16"]
  location            = "eastus"
  resource_group_name = azurerm_resource_group.adlterraformgroup.name
}

resource "azurerm_subnet" "adlterraformsubnet" {
  name                 = "adlSubnet"
  resource_group_name  = azurerm_resource_group.adlterraformgroup.name
  virtual_network_name = azurerm_virtual_network.adlterraformnetwork.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "publicip" {
  name                = "adlTFPublicIP"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.adlterraformgroup.name
  allocation_method   = "Static"
}

resource "azurerm_network_security_group" "adlterraformnsg" {
  name                = "adlNetworkSecurityGroup"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.adlterraformgroup.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "nic" {
  name                = "adlNICVM2"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.adlterraformgroup.name

  ip_configuration {
    name                          = "adlNICConfg"
    subnet_id                     = azurerm_subnet.adlterraformsubnet.id
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = azurerm_public_ip.publicip.id
  }
}

resource "azurerm_virtual_machine" "vm" {
  name                  = "myTFVM"
  location              = "eastus"
  resource_group_name   = azurerm_resource_group.adlterraformgroup.name
  network_interface_ids = [azurerm_network_interface.nic.id]
  vm_size               = "Standard_DS1_v2"

  storage_os_disk {
    name              = "myOsDiskmyTFVM"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04.0-LTS"
    version   = "latest"
  }

  os_profile {
    computer_name  = "myTFVM"
    admin_username = "mateus"
    admin_password = "AstrongP4ss"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }
}

output "public_ip_address" {
  value = azurerm_public_ip.publicip.ip_address
}

resource "null_resource" "upload" {
  provisioner "file" {
    source      = "mysql"
    destination = "/tmp/mysql/"
    connection {
      type     = "ssh"
      user     = "mateus"
      password = "AstrongP4ss"
      host     = azurerm_public_ip.publicip.ip_address
    }
  }
}

resource "null_resource" "deploy" {
  triggers = {
    order = null_resource.upload.id
  }
  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = "mateus"
      password = "AstrongP4ss"
      host     = azurerm_public_ip.publicip.ip_address
    }
    inline = [
      "sudo apt-get update",
      "echo 'mysql-server mysql-server/root_password password AstrongP4ss' | sudo debconf-set-selections",
      "echo 'mysql-server mysql-server/root_password_again password AstrongP4ss' | sudo debconf-set-selections",
      "sudo apt-get -y install mysql-server",
      "sudo chmod 777 /etc/mysql/mysql.conf.d/mysqld.cnf",
      "sudo cat /tmp/mysql/mysqld.cnf > /etc/mysql/mysql.conf.d/mysqld.cnf",
      "sudo service mysql restart",
      "mysql -u root -p'AstrongP4ss' < /tmp/mysql/users.sql 2>/dev/null",
    ]
  }
}