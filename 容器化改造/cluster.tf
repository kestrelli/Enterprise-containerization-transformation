resource "tencentcloud_kubernetes_cluster" "tke_cluster" {
  cluster_name        = "tke-kestrelli-${random_string.suffix.result}(测试自用，勿删)"
  cluster_desc        = "Kubernetes cluster for Kestrelli"
  cluster_version     = var.cluster_version
  container_runtime   = "containerd"
  vpc_id              = tencentcloud_vpc.main.id
  service_cidr        = var.service_cidr
  cluster_max_service_num = 1024
  cluster_max_pod_num = 256
  cluster_deploy_type = "MANAGED_CLUSTER"
  
  network_type         = "VPC-CNI"
  eni_subnet_ids       = [
    tencentcloud_subnet.subnets["primary"].id,
    tencentcloud_subnet.subnets["secondary"].id
  ]
  
# 关键变更：确保内网访问开启
  cluster_intranet          = true

  
  tags = {
    billing = "kestrelli"
    env     = "prod"
    ha      = "multi-az"
  }
}

# 集群端点配置（高可用关键）
resource "tencentcloud_kubernetes_cluster_endpoint" "cluster_endpoint" {
  cluster_id              = tencentcloud_kubernetes_cluster.tke_cluster.id
  cluster_intranet        = true
  cluster_intranet_subnet_id = tencentcloud_subnet.subnets["primary"].id
  
  
  # 确保在节点池创建后启用
  depends_on = [
    tencentcloud_kubernetes_native_node_pool.native_nodepool,
    tencentcloud_kubernetes_serverless_node_pool.super_nodepool
  ]
}

# 原生节点池（跨可用区）
resource "tencentcloud_kubernetes_native_node_pool" "native_nodepool" {
  name                = "native-node-pool-kestrelli"
  cluster_id          = tencentcloud_kubernetes_cluster.tke_cluster.id
  type                = "Native"
  unschedulable       = false
  
  labels {
    name  = "workload-type"
    value = "stable"
  }

  native {
    instance_charge_type     = "POSTPAID_BY_HOUR"
    instance_types           = [var.instance_type]
    security_group_ids       = [tencentcloud_security_group.main.id]
    subnet_ids               = [
      tencentcloud_subnet.subnets["primary"].id,
      tencentcloud_subnet.subnets["secondary"].id
    ]
    auto_repair              = true
    enable_autoscaling       = true
    key_ids                  = ["skey-gigpdrzz"]
    replicas                 = 4  # 最少4个节点保证高可用
    machine_type             = "NativeCVM"
    
    # 高可用分区策略
    scaling {
      min_replicas  = 4
      max_replicas  = 12
      create_policy = "ZoneEquality"  # 确保节点均匀分布
    }
    system_disk {
      disk_type = "CLOUD_PREMIUM"
      disk_size = 100
    }

    data_disks {
        auto_format_and_mount = true
        disk_type             = "CLOUD_PREMIUM"
        disk_size             = 100
        file_system           = "xfs"
        mount_target          = "/var/lib/containerd"
    }

  }
  
  tags {
    resource_type = "machine"
    tags {
      key   = "billing"
      value = "kestrelli"
    }
    tags {
      key   = "ha"
      value = "enabled"
    }
  }
}

# 超级节点池（跨可用区）
resource "tencentcloud_kubernetes_serverless_node_pool" "super_nodepool" {
  cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
  name       = "kestrelli-supernode-ha"
  security_group_ids = [tencentcloud_security_group.main.id]  
  # 主可用区节点
  serverless_nodes {
    display_name = "super-node-1"
    subnet_id    = tencentcloud_subnet.subnets["primary"].id
  }
  # 备用可用区节点
  serverless_nodes {
    display_name = "super-node-2"
    subnet_id    = tencentcloud_subnet.subnets["secondary"].id
  }
  
  # 第三个节点保证高可用
  serverless_nodes {
    display_name = "super-node-backup"
    subnet_id    = tencentcloud_subnet.subnets["primary"].id
  }
  labels = {
    "workload-type" = "elastic"
    "ha"            = "enabled"
  }
  
  lifecycle {
    ignore_changes = [
      serverless_nodes
    ]
  }
}
# kubeconfig输出
resource "local_file" "kubeconfig" {
  filename = "${path.module}/kubeconfig.yaml"
  content  = tencentcloud_kubernetes_cluster_endpoint.cluster_endpoint.kube_config_intranet
  
  provisioner "local-exec" {
    command = "sed -i '' $'s/\r//g' ${path.module}/kubeconfig.yaml"
  }
  depends_on = [tencentcloud_kubernetes_cluster_endpoint.cluster_endpoint]
}

# 使用 Addon 方式安装 HPC 控制器
resource "tencentcloud_kubernetes_addon_attachment" "addon_hpc" {
  cluster_id   = tencentcloud_kubernetes_cluster.tke_cluster.id
  name         = "tke-hpc-controller"
  request_body = <<EOF
  {
    "spec":{
        "chart":{
            "chartName":"tke-hpc-controller",
            "chartVersion":"1.0.7"
        }
    }
  }
EOF

  # 确保在集群端点和节点池创建后安装
  depends_on = [
    tencentcloud_kubernetes_cluster_endpoint.cluster_endpoint,
    tencentcloud_kubernetes_native_node_pool.native_nodepool,
    tencentcloud_kubernetes_serverless_node_pool.super_nodepool
  ]
}