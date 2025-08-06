terraform {
  required_providers {
    # 使用腾讯云官方认可的Provider
    tencentcloud = {
      source  = "tencentcloudstack/tencentcloud"  # 官方推荐源
      version = ">= 1.81.127, < 1.82.0"  # 指定可用版本
    }
  }
}

provider "tencentcloud" {
  region = var.region
  secret_id  = var.tencentcloud_secret_id
  secret_key = var.tencentcloud_secret_key
}

