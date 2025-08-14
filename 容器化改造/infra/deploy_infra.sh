#!/bin/bash

# 获取脚本所在目录作为工作目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR" || exit 1

# 设置腾讯云凭证
read -p "请输入腾讯云SecretId: " TENCENTCLOUD_SECRET_ID
read -s -p "请输入腾讯云SecretKey: " TENCENTCLOUD_SECRET_KEY
echo

# 初始化配置
read -p "请输入区域（默认ap-nanjing）: " REGION
REGION=${REGION:-"ap-nanjing"}
read -p "请输入VPC CIDR（默认172.18.0.0/16）: " VPC_CIDR
VPC_CIDR=${VPC_CIDR:-"172.18.0.0/16"}
read -p "请输入Kubernetes版本（默认1.32.2）: " CLUSTER_VERSION
CLUSTER_VERSION=${CLUSTER_VERSION:-"1.32.2"}
read -p "请输入服务CIDR（默认10.200.0.0/22）: " SERVICE_CIDR
SERVICE_CIDR=${SERVICE_CIDR:-"10.200.0.0/22"}
read -p "请输入节点实例类型（默认SA5.MEDIUM4）: " INSTANCE_TYPE
INSTANCE_TYPE=${INSTANCE_TYPE:-"SA5.MEDIUM4"}

# 在工作目录执行所有操作
echo "=== 在目录 $SCRIPT_DIR 执行操作 ==="

# 清理环境
echo "=== 清理旧环境 ==="
rm -rf .terraform* terraform.tfstate* .terraform.lock.hcl kubeconfig.yaml

# 初始化Terraform
echo "=== 初始化Terraform ==="
terraform init

# 创建基础设施
echo "=== 创建高可用基础设施 ==="
terraform apply -auto-approve \
  -var="tencentcloud_secret_id=$TENCENTCLOUD_SECRET_ID" \
  -var="tencentcloud_secret_key=$TENCENTCLOUD_SECRET_KEY" \
  -var="region=$REGION" \
  -var="vpc_cidr=$VPC_CIDR" \
  -var="cluster_version=$CLUSTER_VERSION" \
  -var="service_cidr=$SERVICE_CIDR" \
  -var="instance_type=$INSTANCE_TYPE" 

# 生成kubeconfig文件
echo "=== 生成高可用集群kubeconfig文件 ==="
terraform apply -auto-approve -target=local_file.kubeconfig

# 输出基础设施信息
echo "=== 高可用基础设施创建完成 ==="
echo "随机后缀: $(terraform output -raw suffix)"
echo "VPC ID: $(terraform output -raw vpc_id)"
echo "安全组 ID: $(terraform output -raw security_group_id)"
echo "子网 ID:"
echo "  primary: $(terraform output -raw subnet_primary_id)"
echo "  secondary: $(terraform output -raw subnet_secondary_id)"
echo "TCR 仓库 URL: $(terraform output -raw tcr_registry_url)"
echo "集群 ID: $(terraform output -raw cluster_id)"
echo "kubeconfig 文件已生成: kubeconfig.yaml"


