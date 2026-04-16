provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

module "cost_tags" {
  source      = "../../modules/nawex-cost-tags"
  environment = "azure-aks"
  owner       = "platform-team"
}

resource "azurerm_resource_group" "nawex" {
  name     = var.resource_group_name
  location = var.location
  tags     = module.cost_tags.tags
}

resource "azurerm_virtual_network" "aks" {
  name                = "${var.cluster_name}-vnet"
  resource_group_name = azurerm_resource_group.nawex.name
  location            = azurerm_resource_group.nawex.location
  address_space       = [var.vnet_cidr]
  tags                = module.cost_tags.tags
}

resource "azurerm_subnet" "aks_nodes" {
  name                 = "${var.cluster_name}-nodes"
  resource_group_name  = azurerm_resource_group.nawex.name
  virtual_network_name = azurerm_virtual_network.aks.name
  address_prefixes     = [var.nodes_subnet_cidr]
}

resource "azurerm_log_analytics_workspace" "aks" {
  name                = "${var.cluster_name}-law"
  resource_group_name = azurerm_resource_group.nawex.name
  location            = azurerm_resource_group.nawex.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = module.cost_tags.tags
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.nawex.location
  resource_group_name = azurerm_resource_group.nawex.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  private_cluster_enabled = var.private_cluster_enabled

  default_node_pool {
    name            = "system"
    vm_size         = var.system_vm_size
    vnet_subnet_id  = azurerm_subnet.aks_nodes.id
    node_count      = var.system_node_count
    os_disk_size_gb = 64
    tags            = module.cost_tags.tags
    # System pool is dedicated to system addons; workloads live on `migrated`.
    only_critical_addons_enabled = true
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    load_balancer_sku = "standard"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id
  }

  role_based_access_control_enabled = true
  tags                              = module.cost_tags.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "migrated" {
  name                  = "migrated"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.workload_vm_size
  vnet_subnet_id        = azurerm_subnet.aks_nodes.id
  min_count             = var.workload_min_count
  max_count             = var.workload_max_count
  auto_scaling_enabled  = true
  node_labels = {
    "nawex.io/workload-class" = "migrated"
    "nawex.io/source"         = "vsphere"
  }
  tags = module.cost_tags.tags
}
