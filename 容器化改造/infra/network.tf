resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# VPC配置
resource "tencentcloud_vpc" "main" {
  name       = "vpc-kestrelli-ha-${random_string.suffix.result}(本人自用，勿动)"
  cidr_block = var.vpc_cidr
  tags = {
    billing = "kestrelli"
    env     = "prod"
    ha      = "enabled"
  }
}

# 多可用区子网配置
resource "tencentcloud_subnet" "subnets" {
  for_each = var.subnets

  name              = "subnet-kestrelli-${each.key}-ha-${random_string.suffix.result}(本人自用，勿动)"
  vpc_id            = tencentcloud_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  tags = {
    billing = "kestrelli"
    type    = each.key
    ha      = "az-${each.value.az}"
  }
}

# 高可用安全组
resource "tencentcloud_security_group" "main" {
  name        = "sg-kestrelli-ha-${random_string.suffix.result}(本人自用，勿动)"
  description = "高可用安全组策略"
  tags = {
    billing = "kestrelli"
    env     = "prod"
    ha      = "enabled"
  }
}

# 安全组规则（高可用优化）
resource "tencentcloud_security_group_rule_set" "rules" {
  security_group_id = tencentcloud_security_group.main.id
  # 高可用API访问
  ingress {
    action      = "ACCEPT"
    cidr_block  = "0.0.0.0/0"
    protocol    = "TCP"
    port        = "22"
    description = "SSH Access"
  }
  
  ingress {
    action      = "ACCEPT"
    cidr_block  = "0.0.0.0/0"
    protocol    = "TCP"
    port        = "6443"
    description = "Kubernetes API Access"
  }
  # 添加内网访问规则
  ingress {
    action      = "ACCEPT"
    cidr_block  = var.vpc_cidr  # 允许整个VPC内的访问
    protocol    = "TCP"
    port        = "6443"
    description = "Kubernetes API Access (Intranet HA)"
  }
  # 节点间通信
  ingress {
    action      = "ACCEPT"
    cidr_block  = var.vpc_cidr
    protocol    = "ALL"
    description = "Node-to-Node Communication"
  }
  egress {
    action      = "ACCEPT"
    cidr_block  = "0.0.0.0/0"
    protocol    = "ALL"
    description = "All Outbound"
  }
}
