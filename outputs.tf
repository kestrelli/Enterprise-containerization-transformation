output "tcr_registry_url" {
  value = tencentcloud_tcr_instance.tcr.public_domain
}

output "vpc_id" {
  value = tencentcloud_vpc.main.id
}

output "security_group_id" {
  value = tencentcloud_security_group.main.id
}

output "subnet_ids" {
  value = {
    for k, subnet in tencentcloud_subnet.subnets : k => subnet.id
  }
}

output "kubeconfig" {
  description = "Kubernetes 集群的 kubeconfig 文件"
  value       = tencentcloud_kubernetes_cluster.tke_cluster.kube_config_intranet
  sensitive   = true
}

output "native_node_pool_id" {
  value = tencentcloud_kubernetes_native_node_pool.native_nodepool.id
}

output "super_node_pool_id" {
  value = tencentcloud_kubernetes_serverless_node_pool.super_nodepool.id
}

output "kubeconfig_intranet" {
  description = "Kubernetes 集群的内网 kubeconfig 文件"
  value       = tencentcloud_kubernetes_cluster.tke_cluster.kube_config_intranet
  sensitive   = true
}

output "suffix" {
  value = random_string.suffix.result
}