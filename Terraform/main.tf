terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.resource_group_name}"
  address_space       = var.vnet_address_space
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "subnet-aks"
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name  = azurerm_resource_group.rg.name
  address_prefixes     = [var.aks_subnet_address_prefix]
}

resource "azurerm_subnet" "redis_subnet" {
  name                                      = "subnet-redis"
  virtual_network_name                      = azurerm_virtual_network.vnet.name
  resource_group_name                       = azurerm_resource_group.rg.name
  address_prefixes                          = [var.redis_subnet_address_prefix]
  private_endpoint_network_policies_enabled = false
}

resource "azurerm_redis_cache" "redis" {
  name                = "redis-voting-app-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  capacity            = 0   # Piano Basic
  family              = "C" # Famiglia Basic/Standard
  sku_name            = "Basic"
  enable_non_ssl_port = false # Best practice: usare solo SSL
  minimum_tls_version = "1.2"
}

resource "azurerm_private_endpoint" "redis_pe" {
  name                = "pe-redis-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.redis_subnet.id

  private_service_connection {
    name                           = "psc-redis"
    private_connection_resource_id = azurerm_redis_cache.redis.id
    is_manual_connection           = false
    subresource_names              = ["redisCache"]
  }
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.redis_dns_zone.id]
  }
}

resource "azurerm_private_dns_zone" "redis_dns_zone" {
  name                = "privatelink.redis.cache.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "vnet_link" {
  name                  = "vnet-link-dns"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.redis_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_container_registry" "acr" {
  name                = "acr${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Basic"
  admin_enabled       = true # Abilitato per la demo
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-voting-app"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "votingapp"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_B2s"
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }

  network_profile {
    network_plugin     = "azure"
    load_balancer_sku  = "standard"
    service_cidr       = "10.200.0.0/16" 
    dns_service_ip     = "10.200.0.10"
    docker_bridge_cidr = "172.17.0.1/16"
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

