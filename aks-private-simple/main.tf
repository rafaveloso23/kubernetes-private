resource "azurerm_resource_group" "rg_aks" {
  name     = "rg-aks-example"
  location = "eastus"
}

resource "azurerm_resource_group" "rg_shared" {
  name     = "rg_shared"
  location = "eastus"


  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

##vnet
resource "azurerm_virtual_network" "vnet_aks" {
  name                = "vnet-hub"
  location            = azurerm_resource_group.rg_aks.location
  resource_group_name = azurerm_resource_group.rg_aks.name
  address_space       = ["10.1.0.0/24"]
}

resource "azurerm_subnet" "snet_pvt" {
  name                              = "snet-pvt"
  resource_group_name               = azurerm_resource_group.rg_aks.name
  virtual_network_name              = azurerm_virtual_network.vnet_aks.name
  address_prefixes                  = ["10.1.0.0/27"]
  private_endpoint_network_policies = "RouteTableEnabled"
}

resource "azurerm_subnet" "snet_aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.rg_aks.name
  virtual_network_name = azurerm_virtual_network.vnet_aks.name
  address_prefixes     = ["10.1.0.128/25"]
}

resource "azurerm_virtual_network" "vnet_shared" {
  name                = "vnet-shared"
  location            = azurerm_resource_group.rg_shared.location
  resource_group_name = azurerm_resource_group.rg_shared.name
  address_space       = ["10.2.0.0/24"]

}

resource "azurerm_subnet" "snet_shared" {
  name                 = "snet-shared"
  resource_group_name  = azurerm_resource_group.rg_shared.name
  virtual_network_name = azurerm_virtual_network.vnet_shared.name
  address_prefixes     = ["10.2.0.0/27"]
}


##vnet peering
resource "azurerm_virtual_network_peering" "aks_shared" {
  name                         = "peer1to2"
  resource_group_name          = azurerm_resource_group.rg_aks.name
  virtual_network_name         = azurerm_virtual_network.vnet_aks.name
  remote_virtual_network_id    = azurerm_virtual_network.vnet_shared.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "shared_aks" {
  name                         = "peer2to1"
  resource_group_name          = azurerm_resource_group.rg_shared.name
  virtual_network_name         = azurerm_virtual_network.vnet_shared.name
  remote_virtual_network_id    = azurerm_virtual_network.vnet_aks.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
}

# ## DNS private
resource "azurerm_private_dns_zone" "pvt_dns_aks" {
  name                = "privatelink.eastus.azmk8s.io"
  resource_group_name = azurerm_resource_group.rg_shared.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "dns_zone_link_aks_vnet" {
  name                  = "dns-link-aks-vnet"
  resource_group_name   = azurerm_resource_group.rg_shared.name
  private_dns_zone_name = azurerm_private_dns_zone.pvt_dns_aks.name
  virtual_network_id    = azurerm_virtual_network.vnet_aks.id
}

# ### Cluster AKS
resource "azurerm_user_assigned_identity" "uai_aks" {
  name                = "aks-example-identity"
  resource_group_name = azurerm_resource_group.rg_aks.name
  location            = azurerm_resource_group.rg_aks.location

}

resource "azurerm_role_assignment" "role_aks_dns" {
  scope                = azurerm_private_dns_zone.pvt_dns_aks.id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.uai_aks.principal_id
}

resource "azurerm_role_assignment" "role_aks_vnet" {
  scope                = azurerm_resource_group.rg_aks.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.uai_aks.principal_id
}

resource "azurerm_key_vault" "example" {
  name                        = "aksrvshcps"
  location                    = azurerm_resource_group.rg_aks.location
  resource_group_name         = azurerm_resource_group.rg_aks.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
      "Create",
      "Delete",
      "GetRotationPolicy",
      "Decrypt",
      "Encrypt",
      "Import",
      "UnwrapKey",
      "Update",
      "Verify",
      "Sign",
      "WrapKey",
      "Release",
      "Rotate",
      "SetRotationPolicy"
    ]

    secret_permissions = [
      "Get",
    ]

    storage_permissions = [
      "Get",
    ]
  }
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_user_assigned_identity.uai_aks.principal_id

    key_permissions = [
      "Get",
      "Create",
      "Delete",
      "GetRotationPolicy",
      "Decrypt",
      "Encrypt",
      "Import",
      "UnwrapKey",
      "Update",
      "Verify",
      "Sign",
      "WrapKey",
      "Release",
      "Rotate",
      "SetRotationPolicy"
    ]

    secret_permissions = [
      "Get",
    ]

    storage_permissions = [
      "Get",
    ]
  }
}
resource "azurerm_key_vault_key" "generated" {
  name         = "generated-certificate"
  key_vault_id = azurerm_key_vault.example.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }

    expire_after         = "P90D"
    notify_before_expiry = "P29D"
  }
}
resource "azurerm_kubernetes_cluster" "example" {
  name                    = "k8s-private-cluster"
  location                = azurerm_resource_group.rg_aks.location
  resource_group_name     = azurerm_resource_group.rg_aks.name
  dns_prefix              = "k8s"
  private_cluster_enabled = true
  private_dns_zone_id     = azurerm_private_dns_zone.pvt_dns_aks.id

  default_node_pool {
    name           = "system"
    node_count     = 1
    vm_size        = "Standard_DS2_v2"
    vnet_subnet_id = azurerm_subnet.snet_aks.id
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.uai_aks.id]
  }

  key_management_service {
    key_vault_key_id         = azurerm_key_vault_key.generated.id
    key_vault_network_access = "Public"
  }
}
data "azurerm_client_config" "current" {}

# resource "azurerm_private_endpoint" "pvt_endpoint_aks" {
#   name                = "example-endpoint"
#   location            = azurerm_resource_group.rg_aks.location
#   resource_group_name = azurerm_resource_group.rg_aks.name
#   subnet_id           = azurerm_subnet.snet_pvt.id

#   private_service_connection {
#     name                           = "example-privateserviceconnection"
#     private_connection_resource_id = azurerm_kubernetes_cluster.example.id
#     subresource_names              = ["management"]
#     is_manual_connection           = false
#   }

#   private_dns_zone_group {
#     name                 = "example-dns-zone-group"
#     private_dns_zone_ids = [
#       azurerm_private_dns_zone.pvt_dns_aks.id,
#     ]
#   }
# }
