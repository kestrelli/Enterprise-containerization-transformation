#!/bin/bash

# 确保Terraform已安装
if ! command -v terraform &> /dev/null; then
    echo "Terraform未安装，请先安装Terraform"
    exit 1
fi

# 设置腾讯云凭证
read -p "请输入腾讯云SecretId: " TENCENTCLOUD_SECRET_ID
read -s -p "请输入腾讯云SecretKey: " TENCENTCLOUD_SECRET_KEY
echo

export TENCENTCLOUD_SECRET_ID=$TENCENTCLOUD_SECRET_ID
export TENCENTCLOUD_SECRET_KEY=$TENCENTCLOUD_SECRET_KEY

# 生成随机后缀
SUFFIX=$(openssl rand -hex 8)
echo "使用随机后缀: $SUFFIX"

# 初始化变量
read -p "请输入区域（默认ap-chengdu）: " REGION
REGION=${REGION:-ap-chengdu}
read -p "请输入VPC CIDR（默认172.18.0.0/16）: " VPC_CIDR
VPC_CIDR=${VPC_CIDR:-172.18.0.0/16}

# 定义子网
PRIMARY_SUBNET_CIDR="172.18.100.0/24"
PRIMARY_SUBNET_AZ="${REGION}-1"
SECONDARY_SUBNET_CIDR="172.18.101.0/24"
SECONDARY_SUBNET_AZ="${REGION}-2"

# 转换为TF_VAR格式
TF_VAR_SUBNETS=$(printf '{"primary":{"cidr":"%s","az":"%s"},"secondary":{"cidr":"%s","az":"%s"}}' \
  "$PRIMARY_SUBNET_CIDR" "$PRIMARY_SUBNET_AZ" \
  "$SECONDARY_SUBNET_CIDR" "$SECONDARY_SUBNET_AZ")

# 集群相关变量
read -p "请输入Kubernetes版本（默认1.32.2）: " CLUSTER_VERSION
CLUSTER_VERSION=${CLUSTER_VERSION:-1.32.2}
read -p "请输入服务CIDR（默认10.200.0.0/22）: " SERVICE_CIDR
SERVICE_CIDR=${SERVICE_CIDR:-10.200.0.0/22}
read -p "请输入节点实例类型（默认SA2.MEDIUM4）: " INSTANCE_TYPE
INSTANCE_TYPE=${INSTANCE_TYPE:-SA2.MEDIUM4}

# 清理环境
rm -rf .terraform* terraform.tfstate* .terraform.lock.hcl

# 初始化Terraform
terraform init -upgrade

# 步骤1: 部署网络资源（包括随机后缀）
echo "=== 部署网络资源 ==="
terraform apply -var="region=$REGION" \
  -var="vpc_cidr=$VPC_CIDR" \
  -var="subnets=$TF_VAR_SUBNETS" \
  -var="suffix=$SUFFIX" \
  -auto-approve

# 步骤2: 部署集群资源
echo "=== 部署集群资源 ==="
terraform apply -var="region=$REGION" \
  -var="vpc_cidr=$VPC_CIDR" \
  -var="subnets=$TF_VAR_SUBNETS" \
  -var="cluster_version=$CLUSTER_VERSION" \
  -var="service_cidr=$SERVICE_CIDR" \
  -var="instance_type=$INSTANCE_TYPE" \
  -var="suffix=$SUFFIX" \
  -auto-approve

# 步骤3: 部署TCR资源
echo "=== 部署TCR资源 ==="
terraform apply -var="region=$REGION" \
  -var="vpc_cidr=$VPC_CIDR" \
  -var="subnets=$TF_VAR_SUBNETS" \
  -var="cluster_version=$CLUSTER_VERSION" \
  -var="service_cidr=$SERVICE_CIDR" \
  -var="instance_type=$INSTANCE_TYPE" \
  -var="suffix=$SUFFIX" \
  -auto-approve

# 输出结果
echo "=== 部署完成 ==="
echo "随机后缀: $SUFFIX"
echo "VPC ID: $(terraform output -raw vpc_id)"
echo "安全组 ID: $(terraform output -raw security_group_id)"
echo "子网 ID:"
terraform output -json subnet_ids | jq -r 'to_entries[] | "  \(.key): \(.value)"'
echo "TCR 仓库 URL: $(terraform output -raw tcr_registry_url)"
echo "Kubeconfig 已保存到 kubeconfig.yaml"
terraform output -raw kubeconfig_intranet > kubeconfig.yaml