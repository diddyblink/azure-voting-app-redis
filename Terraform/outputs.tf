output "kubernetes_cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "kubernetes_cluster_resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "container_registry_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "acr_name" { value = azurerm_container_registry.acr.name }

output "redis_hostname" { value = azurerm_redis_cache.redis.hostname }
