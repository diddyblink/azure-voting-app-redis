variable "resource_group_name" {
  description = "Nome del Resource Group."
  type        = string
  default     = "rg-voting-app-demo"
}

variable "location" {
  description = "Regione di Azure in cui verranno create le risorse."
  type        = string
  default     = "westeurope"
}

variable "vnet_address_space" {
  description = "Range di indirizzi IP per la Virtual Network."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "aks_subnet_address_prefix" {
  description = "Range di indirizzi IP per la Subnet di AKS."
  type        = string
  default     = "10.0.1.0/24"
}

variable "redis_subnet_address_prefix" {
  description = "Range di indirizzi IP per la Subnet di Redis."
  type        = string
  default     = "10.0.2.0/24"
}