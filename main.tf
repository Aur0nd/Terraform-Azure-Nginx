provider "azurerm" {
    features {}
}

resource "azurerm_resource_group" "web-resource-group" {
    name                    = "${var.resource_prefix["key1"]}-resource-group"
    location                = var.location
}   

#Networking
resource "azurerm_virtual_network" "web-virtual-network" {
    name                = "${var.resource_prefix["key2"]}-virtual-network"
    location            = var.location
    resource_group_name = azurerm_resource_group.web-resource-group.name 
    address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "web-subnet" {
    name                 = "${var.resource_prefix["key2"]}-subnet"
    resource_group_name  = azurerm_resource_group.web-resource-group.name
    virtual_network_name = azurerm_virtual_network.web-virtual-network.name
    address_prefixes     = ["10.0.0.0/24"]

}

resource "azurerm_network_security_group" "web-network-security-group" {
    name                = "${var.resource_prefix["key2"]}-security-group"
    location            = var.location
    resource_group_name = azurerm_resource_group.web-resource-group.name
    security_rule {
        name                       = "HTTP"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "80"
        source_address_prefix      = "*"
        destination_address_prefix = "*"       
    }   

    security_rule {
        name                       = "SSH"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"        
    }  
}

resource "azurerm_public_ip" "pip" {
    name                = "public-ip"
    location            = var.location
    resource_group_name = azurerm_resource_group.web-resource-group.name
    sku                 = length(var.zones) == 0 ? "Basic" : "Standard"
    allocation_method   = "Static"
    domain_name_label   = azurerm_resource_group.web-resource-group.name
}


#Load Balancer


resource "azurerm_lb" "web-load-balancers" {
    name                = "web-lb"
    sku                 = length(var.zones) == 0 ? "Basic" : "Standard" #Basic = No AZ
    location            = var.location
    resource_group_name = azurerm_resource_group.web-resource-group.name

    frontend_ip_configuration {
        name                    =  "PublicIPAddress"
        public_ip_address_id    =  azurerm_public_ip.pip.id 
    }       
}

resource "azurerm_lb_backend_address_pool" "web-backend-pool-lb" {
    name                    = "BackEndAddressPool"
    resource_group_name     = azurerm_resource_group.web-resource-group.name 
    loadbalancer_id         = azurerm_lb.web-load-balancers.id
}

resource "azurerm_lb_nat_pool" "web-nat-pool" {
    name                                = "ssh"
    resource_group_name                 = azurerm_resource_group.web-resource-group.name 
    loadbalancer_id                     = azurerm_lb.web-load-balancers.id 
    protocol                            = "Tcp"
    frontend_port_start                 = 50000
    frontend_port_end                   = 50119 
    backend_port                        = 22
    frontend_ip_configuration_name      = "PublicIPAddress"
}

resource "azurerm_lb_probe" "web-lb-probe" {  #HEALTH CHECK
    name                                = "httpd-probe"
    resource_group_name                 = azurerm_resource_group.web-resource-group.name 
    loadbalancer_id                     = azurerm_lb.web-load-balancers.id 
    protocol                            = "http"
    request_path                        = "/"
    port                                = 80
}

resource "azurerm_lb_rule" "web-lb-rule" {
    name                                = "lb-rule"
    resource_group_name                 = azurerm_resource_group.web-resource-group.name 
    loadbalancer_id                     = azurerm_lb.web-load-balancers.id 
    protocol                            = "Tcp"
    frontend_port                       = 80
    backend_port                        = 80
    frontend_ip_configuration_name      = "PublicIPAddress"
    probe_id                            =  azurerm_lb_probe.web-lb-probe.id 
    backend_address_pool_id             =  azurerm_lb_backend_address_pool.web-backend-pool-lb.id 
}





                               # Virtual Machine / Scale Sets

resource "azurerm_virtual_machine_scale_set" "web-scale-set" {
    name                = "${var.resource_prefix["key1"]}-scale-set"
    location            = var.location
    resource_group_name = azurerm_resource_group.web-resource-group.name    

         #Auto Rolling upgrade
    automatic_os_upgrade = true 
    upgrade_policy_mode  = "Rolling"

    rolling_upgrade_policy {
        max_batch_instance_percent              = 20
        max_unhealthy_instance_percent           = 20
        max_unhealthy_upgraded_instance_percent = 5
        pause_time_between_batches              = "PT0S"
    }
         #must, for rolling upgrade policy
    health_probe_id = azurerm_lb_probe.web-lb-probe.id 
    zones           = var.zones 
    sku {
        name       = "Standard_A1_v2"
        tier       = "Standard"
        capacity   = 2
    }
  storage_profile_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
  storage_profile_os_disk {
    name              = ""
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  storage_profile_data_disk {
    lun           = 0
    caching       = "ReadWrite"
    create_option = "Empty"
    disk_size_gb  = 10
  }
  os_profile {
    computer_name_prefix = "avalanche"
    admin_username       = "avalanche"
    custom_data          = "#!/bin/bash\napt-get update && apt-get install -y nginx && systemctl enable nginx && systemctl start nginx"
  }
  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      key_data = file("mykey.pub")
      path     = "/home/avalanche/.ssh/authorized_keys"
    }
  }

  network_profile {
      name          = "networkprofile"
      primary       = true 
      network_security_group_id = azurerm_network_security_group.web-network-security-group.id 
      ip_configuration {
          name                                      = "IPConfiguration"
          primary                                   = true 
          subnet_id                                 = azurerm_subnet.web-subnet.id
          load_balancer_backend_address_pool_ids    = [azurerm_lb_backend_address_pool.web-backend-pool-lb.id]
          load_balancer_inbound_nat_rules_ids       = [azurerm_lb_nat_pool.web-nat-pool.id]
      }
  }
}

resource "azurerm_monitor_autoscale_setting" "web-monitor-autoscale-setting" {
  name                = "web-autoscaling"
  resource_group_name = azurerm_resource_group.web-resource-group.name
  location            = var.location    
  target_resource_id  = azurerm_virtual_machine_scale_set.web-scale-set.id

  profile {
      name = "defaultProfile"
      capacity {
          default = 2
          minimum = 2
          maximum = 4
      }
      rule {
          metric_trigger {
              metric_name       = "Percentage CPU"
              metric_resource_id = azurerm_virtual_machine_scale_set.web-scale-set.id
              time_grain        = "PT1M"
              statistic         = "Average"
              time_window       = "PT5M"
              time_aggregation  = "Average"
              operator          = "GreaterThan"
              threshold         = 40
          }
          scale_action {
              direction = "Increase"
              type      = "ChangeCount"
              value     = "1"
              cooldown  = "PT1M"
          }
      }

      rule {
        metric_trigger {
              metric_name       = "Percentage CPU"
              metric_resource_id = azurerm_virtual_machine_scale_set.web-scale-set.id
              time_grain        = "PT1M"
              statistic         = "Average"
              time_window       = "PT5M"
              time_aggregation  = "Average"
              operator          = "lessThan"
              threshold         = 10
        }
        scale_action {
            direction = "Decrease"
            type      = "ChangeCount"
            value     = "1"
            cooldown  = "PT1M"
        }
      }
  }
  #notification {
  #  email {
  #    send_to_subscription_administrator    = true
  #    send_to_subscription_co_administrator = true
  #    custom_emails                         = ["admin@yourdomain.com"]
  #  }
  #}
}