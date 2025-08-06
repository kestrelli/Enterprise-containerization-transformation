
# outputs.tf
output "suffix" {
  value = random_string.suffix.result
}

output "vpc_id" {
  value = tencentcloud_vpc.main.id
}

output "security_group_id" {
  value = tencentcloud_security_group.main.id
}

output "subnet_primary_id" {
  value = tencentcloud_subnet.subnets["primary"].id
}

output "subnet_secondary_id" {
  value = tencentcloud_subnet.subnets["secondary"].id
}

output "tcr_registry_url" {
  value = tencentcloud_tcr_instance.tcr.public_domain
}

output "cluster_id" {
  value = tencentcloud_kubernetes_cluster.tke_cluster.id
}

output "ha_status" {
  value = {
    multi_az = true
    node_distribution = {
      native_nodes = length(tencentcloud_kubernetes_native_node_pool.native_nodepool.native[0].subnet_ids)
      serverless_nodes = length(tencentcloud_kubernetes_serverless_node_pool.super_nodepool.serverless_nodes)
    }
  }
}
output "kubeconfig" {
  value     = local_file.kubeconfig.filename
  sensitive = true
}