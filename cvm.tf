# 4. CVM实例配置
resource "tencentcloud_instance" "instances" {
  for_each = {
    "primary" = {
      name = "cvm-kestrelli-primary"
      az   = "ap-beijing-3"
      type = "SA2.MEDIUM4"
      subnet = "initial"
    }
    "expansion1" = {
      name = "cvm-kestrelli-exp1"
      az   = "ap-beijing-3"
      type = "SA2.MEDIUM4"
      subnet = "expansion1"
    }
    "expansion2" = {
      name = "cvm-kestrelli-exp2"
      az   = "ap-beijing-6"
      type = "SA2.MEDIUM4"
      subnet = "expansion3"
    }
  }

  instance_name     = each.value.name
  availability_zone = each.value.az
  image_id          = "img-mbevku89"
  instance_type     = each.value.type
  
  vpc_id  = data.tencentcloud_vpc_instances.existing.instance_list[0].vpc_id
  subnet_id = tencentcloud_subnet.subnets[each.value.subnet].id
  
  orderly_security_groups = [tencentcloud_security_group.main.id]
  
  allocate_public_ip        = true
  internet_charge_type      = "TRAFFIC_POSTPAID_BY_HOUR"
  internet_max_bandwidth_out = 10
  
  system_disk_type = "CLOUD_PREMIUM"
  system_disk_size = 50

  user_data = base64encode(<<-EOT
    #!/bin/bash
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.d/99-sysctl.conf
    sysctl -p
    apt-get update -y
    apt-get install -y docker.io
  EOT
  )
  
  tags = {
    billing = "kestrelli"
    type    = each.key
  }
}

# 输出配置
output "public_ips" {
  value = {
    for k, instance in tencentcloud_instance.instances : k => instance.public_ip
  }
}