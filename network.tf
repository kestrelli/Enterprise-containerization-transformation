resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "tencentcloud_vpc" "main" {
  name       = "vpc-kestrelli-${random_string.suffix.result}"
  cidr_block = var.vpc_cidr
  tags = {
    billing = "kestrelli"
    env     = "prod"
  }
}

resource "tencentcloud_subnet" "subnets" {
  for_each = var.subnets

  name              = "subnet-kestrelli-${each.key}"
  vpc_id            = tencentcloud_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  tags = {
    billing = "kestrelli"
    type    = each.key
  }
}

resource "tencentcloud_security_group" "main" {
  name        = "sg-kestrelli-${random_string.suffix.result}"
  description = "统一安全组策略"
  tags = {
    billing = "kestrelli"
    env     = "prod"
  }
}

resource "tencentcloud_security_group_rule_set" "rules" {
  security_group_id = tencentcloud_security_group.main.id

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
  
  egress {
    action      = "ACCEPT"
    cidr_block  = "0.0.0.0/0"
    protocol    = "ALL"
    description = "All Outbound"
  }
}