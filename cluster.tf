resource "tencentcloud_kubernetes_cluster" "tke_cluster" {
  cluster_name        = "tke-kestrelli-${random_string.suffix.result}"
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
  
  cluster_internet          = false
  cluster_intranet          = true
  cluster_intranet_subnet_id = tencentcloud_subnet.subnets["primary"].id
  
  worker_config {
    count                = 1
    instance_type        = var.instance_type
    availability_zone    = var.subnets["primary"].az
    subnet_id            = tencentcloud_subnet.subnets["primary"].id
    system_disk_type     = "CLOUD_PREMIUM"
    system_disk_size     = 50
    security_group_ids   = [tencentcloud_security_group.main.id]
    key_ids              = ["skey-g6n08a8l"]
    
    data_disk {
      disk_type = "CLOUD_PREMIUM"
      disk_size = 100
    }
  }
  
  tags = {
    billing = "kestrelli"
    env     = "prod"
  }
}

resource "tencentcloud_kubernetes_native_node_pool" "native_nodepool" {
  name                = "native-node-pool"
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
    key_ids                  = ["skey-g6n08a8l"]
    replicas                 = 2
    machine_type             = "NativeCVM"

    system_disk {
      disk_type = "CLOUD_PREMIUM"
      disk_size = 50
    }

    data_disks {
        auto_format_and_mount = true
        disk_type             = "CLOUD_PREMIUM"
        disk_size             = 100
        file_system           = "xfs"
        mount_target          = "/var/lib/containerd"
    }

    scaling {
      min_replicas  = 2
      max_replicas  = 6
      create_policy = "ZoneEquality"
    }
  }
  
  tags {
    resource_type = "machine"
    tags {
      key   = "billing"
      value = "kestrelli"
    }
  }
}

resource "tencentcloud_kubernetes_serverless_node_pool" "super_nodepool" {
  cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
  name       = "kestrelli-supernode"

  serverless_nodes {
    display_name = "super-node-1"
    subnet_id    = tencentcloud_subnet.subnets["primary"].id
  }

  serverless_nodes {
    display_name = "super-node-2"
    subnet_id    = tencentcloud_subnet.subnets["secondary"].id
  }

  security_group_ids = [tencentcloud_security_group.main.id]
  
  labels = {
    "workload-type" = "elastic"
  }
  
  lifecycle {
    ignore_changes = [
      serverless_nodes
    ]
  }
}