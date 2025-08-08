
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


output "kubeconfig" {
  value     = local_file.kubeconfig.filename
  sensitive = true
}