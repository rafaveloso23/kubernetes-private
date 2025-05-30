resource "azurerm_resource_group" "rg-hub" {
  name     = "rg-hub"
  location = "eastus"
  tags     = var.tags

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "azurerm_resource_group" "rg-spoke" {
  name     = "rg-spoke"
  location = "eastus"
  tags     = var.tags

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "azurerm_resource_group" "rg-shared" {
  name     = "rg-shared"
  location = "eastus"
  tags     = var.tags

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

##vnet
resource "azurerm_virtual_network" "vnet-hub" {
  name                = "vnet-hub"
  location            = azurerm_resource_group.rg-hub.location
  resource_group_name = azurerm_resource_group.rg-hub.name
  address_space       = ["10.0.0.0/24"]

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }

  tags = {
    environment = "aks"
  }
}

resource "azurerm_subnet" "snet-fw" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.rg-hub.name
  virtual_network_name = azurerm_virtual_network.vnet-hub.name
  address_prefixes     = ["10.0.0.128/25"]
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.rg-hub.name
  virtual_network_name = azurerm_virtual_network.vnet-hub.name
  address_prefixes     = ["10.0.0.0/25"]
}

##vpn
resource "azurerm_public_ip" "vpn" {
  name                = "pub-vpn"
  location            = azurerm_resource_group.rg-hub.location
  resource_group_name = azurerm_resource_group.rg-hub.name

  allocation_method = "Dynamic"

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "azurerm_virtual_network_gateway" "example" {
  name                = "vngw-test"
  location            = azurerm_resource_group.rg-hub.location
  resource_group_name = azurerm_resource_group.rg-hub.name

  type     = "Vpn"
  vpn_type = "RouteBased"

  active_active = false
  enable_bgp    = false
  sku           = "Standard"

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }

  vpn_client_configuration {
    address_space        = ["192.168.10.0/24"]
    aad_audience         = "41b23e61-6c1e-4545-b367-cd054e0ed4b4"
    aad_issuer           = "https://sts.windows.net/0eed3ea8-f35c-4862-b14a-9809318064c7/"
    aad_tenant           = "https://login.microsoftonline.com/0eed3ea8-f35c-4862-b14a-9809318064c7"
    vpn_client_protocols = ["OpenVPN"]

  }
  depends_on = [azurerm_subnet.gateway, azurerm_public_ip.vpn]
}

##vnet shared zones
resource "azurerm_virtual_network" "vnet-shared" {
  name                = "vnet-shared"
  location            = azurerm_resource_group.rg-shared.location
  resource_group_name = azurerm_resource_group.rg-shared.name
  address_space       = ["10.0.8.0/24"]

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }

  tags = {
    environment = "aks"
  }
}

resource "azurerm_subnet" "snet-shared" {
  name                 = "privateendpoints"
  resource_group_name  = azurerm_resource_group.rg-shared.name
  virtual_network_name = azurerm_virtual_network.vnet-shared.name
  address_prefixes     = ["10.0.8.0/24"]
}

resource "azurerm_route_table" "example2" {
  name                          = "rt-sh"
  location                      = azurerm_resource_group.rg-shared.location
  resource_group_name           = azurerm_resource_group.rg-shared.name
  disable_bgp_route_propagation = false

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }

  route {
    name                   = "shred"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.example.ip_configuration[0].private_ip_address
  }

}

resource "azurerm_subnet_route_table_association" "example2" {
  subnet_id      = azurerm_subnet.snet-shared.id
  route_table_id = azurerm_route_table.example2.id
}

#vnet aks
resource "azurerm_virtual_network" "vnet-spoke" {
  name                = "vnet-spoke"
  location            = azurerm_resource_group.rg-spoke.location
  resource_group_name = azurerm_resource_group.rg-spoke.name
  address_space       = ["192.0.0.0/16"]
  dns_servers         = [azurerm_firewall.example.ip_configuration[0].private_ip_address, "8.8.8.8"]

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
  tags = {
    environment = "aks"
  }
}

resource "azurerm_subnet" "snet-aks" {
  name                 = "subnet-aks"
  resource_group_name  = azurerm_resource_group.rg-spoke.name
  virtual_network_name = azurerm_virtual_network.vnet-spoke.name
  address_prefixes     = ["192.0.1.0/24"]
}

resource "azurerm_subnet" "snet-appgw" {
  name                 = "subnet-appgw"
  resource_group_name  = azurerm_resource_group.rg-spoke.name
  virtual_network_name = azurerm_virtual_network.vnet-spoke.name
  address_prefixes     = ["192.0.2.0/24"]
}

resource "azurerm_subnet_network_security_group_association" "sg-appgw" {
  subnet_id                 = azurerm_subnet.snet-appgw.id
  network_security_group_id = azurerm_network_security_group.sg-appgw.id

  depends_on = [azurerm_network_security_rule.sg-appgw-1, azurerm_network_security_rule.sg-appgw-2, azurerm_network_security_rule.sg-appgw-3, azurerm_network_security_rule.sg-appgw-4]
}

resource "azurerm_network_security_group" "sg-appgw" {
  name                = "appgw-security-group"
  location            = azurerm_resource_group.rg-spoke.location
  resource_group_name = azurerm_resource_group.rg-spoke.name

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "azurerm_network_security_rule" "sg-appgw-1" {
  name                        = "Client-traffic"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "80-443"
  source_address_prefix       = "*"
  destination_address_prefix  = "192.0.2.0/24"
  resource_group_name         = azurerm_resource_group.rg-spoke.name
  network_security_group_name = azurerm_network_security_group.sg-appgw.name
}

resource "azurerm_network_security_rule" "sg-appgw-2" {
  name                        = "Infrastructure-ports"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "65200-65535"
  source_address_prefix       = "GatewayManager"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg-spoke.name
  network_security_group_name = azurerm_network_security_group.sg-appgw.name
}

resource "azurerm_network_security_rule" "sg-appgw-3" {
  name                        = "Azure-Load-Balancer-probes"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg-spoke.name
  network_security_group_name = azurerm_network_security_group.sg-appgw.name
}

resource "azurerm_network_security_rule" "sg-appgw-4" {
  name                        = "Outbound-to-the-Internet"
  priority                    = 130
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "Internet"
  resource_group_name         = azurerm_resource_group.rg-spoke.name
  network_security_group_name = azurerm_network_security_group.sg-appgw.name
}

resource "azurerm_subnet" "snet-teste" {
  name                 = "subnet-service"
  resource_group_name  = azurerm_resource_group.rg-spoke.name
  virtual_network_name = azurerm_virtual_network.vnet-spoke.name
  address_prefixes     = ["192.0.4.0/24"]
}


##Appgw
locals {
  backend_address_pool_name              = "${azurerm_virtual_network.vnet-spoke.name}-beap"
  frontend_port_name                     = "${azurerm_virtual_network.vnet-spoke.name}-feport"
  frontend_ip_configuration_name         = "${azurerm_virtual_network.vnet-spoke.name}-feip"
  http_setting_name                      = "${azurerm_virtual_network.vnet-spoke.name}-be-htst"
  listener_name                          = "${azurerm_virtual_network.vnet-spoke.name}-httplstn"
  request_routing_rule_name              = "${azurerm_virtual_network.vnet-spoke.name}-rqrt"
  frontend_ip_configuration_name_private = "private-config"
}


resource "azurerm_public_ip" "test" {
  name                = "publicIp1"
  location            = azurerm_resource_group.rg-spoke.location
  resource_group_name = azurerm_resource_group.rg-spoke.name
  allocation_method   = "Static"
  sku                 = "Standard"
  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}
resource "azurerm_application_gateway" "network" {
  name                = "appgw-aks"
  resource_group_name = azurerm_resource_group.rg-spoke.name
  location            = azurerm_resource_group.rg-spoke.location
  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = azurerm_subnet.snet-appgw.id
  }

  frontend_port {
    name = local.frontend_port_name
    port = 80
  }

  frontend_port {
    name = "httpsPort"
    port = 443
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.test.id
  }

  frontend_ip_configuration {
    name                          = local.frontend_ip_configuration_name_private
    private_ip_address            = "192.0.2.8"
    private_ip_address_allocation = "Static"
    subnet_id                     = azurerm_subnet.snet-appgw.id
  }

  backend_address_pool {
    name = local.backend_address_pool_name
    #svc controller from ingress nginx
    ip_addresses = ["192.0.1.9"]
  }

  backend_http_settings {
    name                                = local.http_setting_name
    cookie_based_affinity               = "Disabled"
    port                                = 80
    protocol                            = "Http"
    request_timeout                     = 1
    pick_host_name_from_backend_address = true
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name_private
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.request_routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
    priority                   = 1
    rewrite_rule_set_name      = "x-forwarded-for-01"
  }

  rewrite_rule_set {
    name = "x-forwarded-for-01"
    rewrite_rule {
      name          = "x-forwarded-for-01"
      rule_sequence = 100
      request_header_configuration {
        header_name  = "X-Forwarded-For"
        header_value = "{var_add_x_forwarded_for_proxy}"
      }

    }
  }

  depends_on = [azurerm_virtual_network.vnet-spoke, azurerm_public_ip.test, azurerm_subnet.snet-appgw]
}

## Route table AKS
resource "azurerm_route_table" "example" {
  name                          = "rt-fw"
  location                      = azurerm_resource_group.rg-spoke.location
  resource_group_name           = azurerm_resource_group.rg-spoke.name
  disable_bgp_route_propagation = false

  route {
    name                   = "fwrn"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.example.ip_configuration[0].private_ip_address
  }
  lifecycle {
    ignore_changes = [route, tags]
  }

}

resource "azurerm_subnet_route_table_association" "example" {
  subnet_id      = azurerm_subnet.snet-aks.id
  route_table_id = azurerm_route_table.example.id

  depends_on = [azurerm_route_table.example, azurerm_subnet.snet-aks]
}

##vnet peering
resource "azurerm_virtual_network_peering" "example-1" {
  name                         = "peer1to2"
  resource_group_name          = azurerm_resource_group.rg-spoke.name
  virtual_network_name         = azurerm_virtual_network.vnet-spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.vnet-hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = true

}

resource "azurerm_virtual_network_peering" "example-2" {
  name                         = "peer2to1"
  resource_group_name          = azurerm_resource_group.rg-hub.name
  virtual_network_name         = azurerm_virtual_network.vnet-hub.name
  remote_virtual_network_id    = azurerm_virtual_network.vnet-spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
}

resource "azurerm_virtual_network_peering" "example-3" {
  name                         = "peer1to3"
  resource_group_name          = azurerm_resource_group.rg-shared.name
  virtual_network_name         = azurerm_virtual_network.vnet-shared.name
  remote_virtual_network_id    = azurerm_virtual_network.vnet-hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = true
  
}

resource "azurerm_virtual_network_peering" "example-4" {
  name                         = "peer3to1"
  resource_group_name          = azurerm_resource_group.rg-hub.name
  virtual_network_name         = azurerm_virtual_network.vnet-hub.name
  remote_virtual_network_id    = azurerm_virtual_network.vnet-shared.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
}


###Firewall

resource "azurerm_public_ip" "example" {
  name                = "testpip"
  location            = azurerm_resource_group.rg-hub.location
  resource_group_name = azurerm_resource_group.rg-hub.name
  allocation_method   = "Static"
  sku                 = "Standard"

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "azurerm_firewall" "example" {
  name                = "testfirewall"
  location            = azurerm_resource_group.rg-hub.location
  resource_group_name = azurerm_resource_group.rg-hub.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.snet-fw.id
    public_ip_address_id = azurerm_public_ip.example.id
  }

  dns_servers = ["168.63.129.16"]

  lifecycle {
    ignore_changes = [dns_servers, tags]
  }
}

resource "azurerm_firewall_network_rule_collection" "example" {
  name                = "aksfwnr"
  azure_firewall_name = azurerm_firewall.example.name
  resource_group_name = azurerm_resource_group.rg-hub.name
  priority            = 100
  action              = "Allow"

  #### novas rules
  rule {
    name                  = "Time"
    source_addresses      = ["*"]
    destination_ports     = ["123"]
    destination_addresses = ["*"]
    protocols             = ["UDP"]
  }

  rule {
    name                  = "DNS"
    source_addresses      = ["*"]
    destination_ports     = ["53"]
    destination_addresses = ["*"]
    protocols             = ["UDP"]
  }

  rule {
    name              = "ServiceTags"
    source_addresses  = ["*"]
    destination_ports = ["*"]
    destination_addresses = [
      "AzureContainerRegistry",
      "MicrosoftContainerRegistry",
      "AzureActiveDirectory"
    ]
    protocols = ["Any"]
  }

  rule {
    name                  = "Internet"
    source_addresses      = ["*"]
    destination_ports     = ["*"]
    destination_addresses = ["*"]
    protocols             = ["TCP"]
  }
}

resource "azurerm_firewall_application_rule_collection" "example" {
  name                = "aksfwar"
  azure_firewall_name = azurerm_firewall.example.name
  resource_group_name = azurerm_resource_group.rg-hub.name
  priority            = 100
  action              = "Allow"

  ### novas rules
  rule {
    name             = "AllowMicrosoftFqdns"
    source_addresses = ["*"]

    target_fqdns = [
      "*.cdn.mscr.io",
      "mcr.microsoft.com",
      "*.data.mcr.microsoft.com",
      "management.azure.com",
      "login.microsoftonline.com",
      "acs-mirror.azureedge.net",
      "dc.services.visualstudio.com",
      "*.opinsights.azure.com",
      "*.oms.opinsights.azure.com",
      "*.microsoftonline.com",
      "*.monitoring.azure.com",
    ]

    protocol {
      port = "80"
      type = "Http"
    }

    protocol {
      port = "443"
      type = "Https"
    }
  }
  rule {
    name             = "AllowGit"
    source_addresses = ["*"]

    target_fqdns = [
      "raw.githubusercontent.com"
    ]

    protocol {
      port = "80"
      type = "Http"
    }

    protocol {
      port = "443"
      type = "Https"
    }
  }
  rule {
    name             = "AllowFqdnsForOsUpdates"
    source_addresses = ["*"]

    target_fqdns = [
      "download.opensuse.org",
      "security.ubuntu.com",
      "ntp.ubuntu.com",
      "packages.microsoft.com",
      "snapcraft.io"
    ]

    protocol {
      port = "80"
      type = "Http"
    }

    protocol {
      port = "443"
      type = "Https"
    }
  }
  rule {
    name             = "AllowImagesFqdns"
    source_addresses = ["*"]

    target_fqdns = [
      "auth.docker.io",
      "registry-1.docker.io",
      "production.cloudflare.docker.com"
    ]

    protocol {
      port = "80"
      type = "Http"
    }

    protocol {
      port = "443"
      type = "Https"
    }
  }
  rule {
    name             = "AllowBing"
    source_addresses = ["*"]

    target_fqdns = [
      "*.bing.com"
    ]

    protocol {
      port = "80"
      type = "Http"
    }

    protocol {
      port = "443"
      type = "Https"
    }
  }
  rule {
    name             = "AllowGoogle"
    source_addresses = ["*"]

    target_fqdns = [
      "*.google.com"
    ]

    protocol {
      port = "80"
      type = "Http"
    }

    protocol {
      port = "443"
      type = "Https"
    }
  }
}

## DNS private

resource "azurerm_private_dns_zone" "example" {
  name                = "privatelink.eastus.azmk8s.io"
  resource_group_name = azurerm_resource_group.rg-shared.name
  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "example1" {
  name                  = "vnet-shared"
  resource_group_name   = azurerm_resource_group.rg-shared.name
  private_dns_zone_name = azurerm_private_dns_zone.example.name
  virtual_network_id    = azurerm_virtual_network.vnet-shared.id

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "example2" {
  name                  = "vnet-hub"
  resource_group_name   = azurerm_resource_group.rg-shared.name
  private_dns_zone_name = azurerm_private_dns_zone.example.name
  virtual_network_id    = azurerm_virtual_network.vnet-hub.id

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "example3" {
  name                  = "vnet-spoke"
  resource_group_name   = azurerm_resource_group.rg-shared.name
  private_dns_zone_name = azurerm_private_dns_zone.example.name
  virtual_network_id    = azurerm_virtual_network.vnet-spoke.id

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "azurerm_user_assigned_identity" "example" {
  name                = "aks-example-identity"
  resource_group_name = azurerm_resource_group.rg-spoke.name
  location            = azurerm_resource_group.rg-spoke.location

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "azurerm_role_assignment" "example" {
  scope                = azurerm_private_dns_zone.example.id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.example.principal_id
}


resource "azurerm_role_assignment" "example2" {
  scope                = azurerm_resource_group.rg-spoke.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.example.principal_id
}

### Cluster AKS

resource "azurerm_kubernetes_cluster" "example" {
  name                    = "k8s"
  location                = azurerm_resource_group.rg-spoke.location
  resource_group_name     = azurerm_resource_group.rg-spoke.name
  dns_prefix              = "k8s"
  private_cluster_enabled = true
  private_dns_zone_id     = azurerm_private_dns_zone.example.id

  default_node_pool {
    name           = "system"
    node_count     = 1
    vm_size        = "Standard_DS2_v2"
    vnet_subnet_id = azurerm_subnet.snet-aks.id
  }

  lifecycle {
    ignore_changes = [
      default_node_pool, tags,
    ]
  }


  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
    outbound_type     = "userDefinedRouting"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.example.id]

  }

  depends_on = [
    azurerm_role_assignment.example, azurerm_role_assignment.example2, azurerm_firewall_network_rule_collection.example, azurerm_firewall_application_rule_collection.example, azurerm_subnet.snet-aks, azurerm_subnet_route_table_association.example
  ]

}

resource "azurerm_kubernetes_cluster_node_pool" "example" {
  name                  = "internal"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.example.id
  vm_size               = "Standard_DS2_v2"
  node_count            = 1
  lifecycle {
    ignore_changes = [
      vnet_subnet_id, tags,
    ]
  }
  tags = {
    Environment = "Production"
  }



  depends_on = [
    azurerm_kubernetes_cluster.example, azurerm_role_assignment.example, azurerm_role_assignment.example2, azurerm_firewall_network_rule_collection.example, azurerm_firewall_application_rule_collection.example, azurerm_subnet.snet-aks, azurerm_subnet_route_table_association.example
  ]
}

## Acr
resource "azurerm_container_registry" "example" {
  name                = "acrrveloso"
  resource_group_name = azurerm_resource_group.rg-spoke.name
  location            = azurerm_resource_group.rg-spoke.location
  sku                 = "Standard"

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "azurerm_role_assignment" "example1" {
  principal_id                     = azurerm_kubernetes_cluster.example.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.example.id
  skip_service_principal_aad_check = true
}
