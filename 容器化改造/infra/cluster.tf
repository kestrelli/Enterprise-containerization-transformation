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
  
# 确保内网访问开启
  cluster_intranet          = false
  
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
    tencentcloud_kubernetes_native_node_pool.native_nodepool-nj1, 
    tencentcloud_kubernetes_native_node_pool.native_nodepool-nj3,  
    tencentcloud_kubernetes_serverless_node_pool.super_nodepool
  ]
}

# 南京一区专用节点池（primary子网）
resource "tencentcloud_kubernetes_native_node_pool" "native_nodepool-nj1"  {
  name                = "native-node-pool-nj1"
  cluster_id          = tencentcloud_kubernetes_cluster.tke_cluster.id
  type                = "Native"
  unschedulable       = false
  
  labels {
    name  = "workload-type"
    value = "stable"
  }

  native {
    instance_charge_type = "POSTPAID_BY_HOUR"
    instance_types       = [var.instance_type]
    security_group_ids   = [tencentcloud_security_group.main.id]
    subnet_ids           = [tencentcloud_subnet.subnets["primary"].id] # 仅使用primary子网
    
    key_ids              = ["skey-gigpdrzz"]
    replicas             = 2  # 可用区1节点数
    machine_type         = "Native"
    
    scaling {
      min_replicas  = 2
      max_replicas  = 6
      create_policy = "ZoneEquality"  # 确保节点均匀分布
      # 无多AZ策略，节点都在NJ1
    }
    
    system_disk {
      disk_type = "CLOUD_BSSD"
      disk_size = 100
    }

    data_disks {
      auto_format_and_mount = true
      disk_type             = "CLOUD_BSSD"
      disk_size             = 100
      file_system           = "ext4"
      mount_target          = "/var/lib/container"
    }
  }
  lifecycle {
    ignore_changes = [
      native[0].instance_types,  # 锁定实例类型
      native[0].system_disk      # 同时锁定磁盘配置
    ]
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

# 南京三区专用节点池（secondary子网）
resource "tencentcloud_kubernetes_native_node_pool" "native_nodepool-nj3"  {
  name                = "native-node-pool-nj3"
  cluster_id          = tencentcloud_kubernetes_cluster.tke_cluster.id
  type                = "Native"
  unschedulable       = false
  
  labels {
    name  = "workload-type"
    value = "stable"
  }

  native {
    instance_charge_type = "POSTPAID_BY_HOUR"
    instance_types       = [var.instance_type]
    security_group_ids   = [tencentcloud_security_group.main.id]
    subnet_ids           = [tencentcloud_subnet.subnets["secondary"].id] # 仅使用secondary子网
    
    key_ids              = ["skey-gigpdrzz"]
    replicas             = 2  # 可用区3节点数
    machine_type         = "Native"
    
    scaling {
      min_replicas  = 2
      max_replicas  = 6
      create_policy = "ZoneEquality"  # 确保节点均匀分布
    }
    
    system_disk {
      disk_type = "CLOUD_BSSD"
      disk_size = 100
    }

    data_disks {
      auto_format_and_mount = true
      disk_type             = "CLOUD_BSSD"
      disk_size             = 100
      file_system           = "ext4"
      mount_target          = "/var/lib/container"
    }
  }
  lifecycle {
    ignore_changes = [
      native[0].instance_types,  # 锁定实例类型
      native[0].system_disk      # 同时锁定磁盘配置
    ]
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

# 使用 Addon 方式安装 HPC 控制器（最新官方推荐方式）
resource "tencentcloud_kubernetes_addon" "addon_hpc" {
  cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
  addon_name = "tke-hpc-controller"  # 使用 addon_name 

  # 确保在集群端点和节点池创建后安装
  depends_on = [
    tencentcloud_kubernetes_cluster_endpoint.cluster_endpoint,
    tencentcloud_kubernetes_native_node_pool.native_nodepool-nj1,
    tencentcloud_kubernetes_native_node_pool.native_nodepool-nj3,
    tencentcloud_kubernetes_serverless_node_pool.super_nodepool
  ]
}
# 新增：使用 Addon 方式安装日志采集组件
resource "tencentcloud_kubernetes_addon" "addon_log_agent" {
  cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
  addon_name = "tke-log-agent"  # 固定名称
  
  # 确保在集群端点和节点池创建后安装
  depends_on = [
    tencentcloud_kubernetes_cluster_endpoint.cluster_endpoint,
    tencentcloud_kubernetes_serverless_node_pool.super_nodepool
  ]
}
