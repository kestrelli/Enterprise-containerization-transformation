variable "region" {
  description = "腾讯云区域"
  default     = "ap-chengdu"
}

variable "vpc_cidr" {
  description = "VPC CIDR 范围"
  default     = "172.18.0.0/16"
}

variable "subnets" {
  description = "子网配置"
  type = map(object({
    cidr = string
    az   = string
  }))
  default = {
    "primary" = {
      cidr = "172.18.100.0/24"
      az   = "ap-chengdu-1"
    }
    "secondary" = {
      cidr = "172.18.101.0/24"
      az   = "ap-chengdu-2"
    }
  }
}

variable "cluster_version" {
  description = "Kubernetes 集群版本"
  default     = "1.32.2"
}

variable "service_cidr" {
  description = "Kubernetes 服务 CIDR"
  default     = "10.200.0.0/22"
}

variable "instance_type" {
  description = "节点实例类型"
  default     = "SA2.MEDIUM4"
}

variable "suffix" {
  description = "随机后缀"
  type        = string
}