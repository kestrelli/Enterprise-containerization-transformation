variable "region" {
  description = "腾讯云区域"
  default     = "ap-nanjing"
}
variable "tencentcloud_secret_id" {
  description = "腾讯云SecretId"
  type        = string
  sensitive   = true
}

variable "tencentcloud_secret_key" {
  description = "腾讯云SecretKey"
  type        = string
  sensitive   = true
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
      az   = "ap-nanjing-1"
    }
    "secondary" = {
      cidr = "172.18.101.0/24"
      az   = "ap-nanjing-3"
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
variable "image_tag" {
  description = "Docker 镜像标签"
  default     = "latest"
}
variable "tke_addon_version" {
  description = "TKE 附加组件版本"
  default     = "1.0.7"
}
variable "cluster_id" {
  description = "TKE cluster id"
  type        = string
  default     = ""
}